defmodule Mehungry.FoodData.Usda.SchemaMatcher do
  @moduledoc """
  Groups the app's ingredients by the **structural pattern** ("schema") of their
  USDA description, where the set of valid schemas is inherited from reference
  USDA datasets.

  A *schema* is the field signature produced by the deterministic description
  parser (`Mehungry.FoodData.Usda.Parser.Pipeline`): the ordered set of semantic
  dimensions the parse populated — e.g. `[:canonical_food, :processing,
  :packaging]` — independent of the concrete values. Two descriptions share a
  schema iff they populate exactly the same dimensions.

  The **predefined catalog** of schemas is derived by parsing the descriptions
  in the reference FDC datasets (FoundationFoods / SRLegacyFoods / SurveyFoods)
  found at the JSON paths configured under `:usda_schema_reference_paths`. When
  no reference file is readable the catalog falls back to the app's own
  fdc-backed ingredient corpus, so the view stays functional without shipping
  the multi-MB datasets. `source` on the analysis reports which was used.

  On top of the derived catalog sits a small hand-authored registry of
  **predefined patterns** (`@predefined_patterns`) — positional templates whose
  leading comma-segment is a `type` discriminator the deterministic parser would
  otherwise skip (e.g. `Alcoholic Beverage, {food}, {sub_type}, {color},
  {variety}`). These are matched *before* the parser, so such descriptions group
  under their named pattern instead of falling out as unparseable. The shared
  parser is left untouched — this recognition is local to the schema view.

  `analyze/0` buckets every fdc-backed ingredient: a predefined-pattern match
  wins first; otherwise an ingredient whose parser signature is a known schema
  is *matched* to it; one the parser skips, that yields no base food, or whose
  signature is absent from the catalog is set aside as *unmatched*.

  All work is on-demand (mount + explicit recompute), never on a timer — it
  parses the whole corpus and is deliberately heavy.
  """

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.FoodData.Usda.Parser.{Pipeline, Result}
  alias Mehungry.Repo

  @config_key :usda_schema_reference_paths
  @reference_dataset_keys ~w(FoundationFoods SRLegacyFoods SurveyFoods)
  @max_reference_examples 3

  # Semantic dimensions in display order: {Result field, short label}. The
  # presence of each (see `populated?/2`) forms a description's signature.
  # `:canonical_food` is the base food and is required for any match.
  @dimensions [
    {:canonical_food, "food"},
    {:harvest_stage, "harvest"},
    {:processing, "processing"},
    {:processing_modifiers, "modifiers"},
    {:packaging, "packaging"},
    {:part, "part"},
    {:dismemberment, "cut"},
    {:bone_state, "bone"},
    {:portion, "portion"},
    {:grade, "grade"},
    {:fat, "fat"}
  ]

  # Hand-authored positional templates matched ahead of the parser. `type` is
  # the normalized leading comma-segment that identifies the pattern; `slots`
  # are the labeled dimensions the remaining segments fill positionally (the
  # first slot is always `:type`). A description fits when its leading segment
  # equals `type` and it has no more segments than the template has slots.
  @predefined_patterns [
    %{
      type: "alcoholic beverage",
      label: "Alcoholic Beverage",
      slots: [:type, :canonical_food, :beverage_sub_type, :color, :variety]
    }
  ]

  @typedoc "One derived schema plus the ingredients matched to it."
  @type schema :: %{
          key: String.t(),
          label: String.t(),
          dimensions: [atom()],
          reference_count: non_neg_integer(),
          reference_examples: [String.t()],
          matched: [ingredient()],
          matched_count: non_neg_integer()
        }

  @type ingredient :: %{
          id: pos_integer(),
          name: String.t(),
          data_type: String.t() | nil,
          food_class: String.t() | nil
        }
  @type unmatched :: %{ingredient: ingredient(), reason: String.t()}

  @doc """
  Builds the schema catalog from the reference source, then buckets every
  fdc-backed ingredient. Returns a map with `:schemas` (most-matched first),
  `:unmatched`, `:source`, and corpus totals.

  `opts` are forwarded to the parser; pass `:vocabulary` in tests to parse
  against a fixture vocabulary instead of the DB-backed one.
  """
  @spec analyze(keyword()) :: %{
          source: :reference_files | :ingredients,
          schemas: [schema()],
          unmatched: [unmatched()],
          total_ingredients: non_neg_integer(),
          matched_count: non_neg_integer(),
          unmatched_count: non_neg_integer(),
          schema_count: non_neg_integer()
        }
  def analyze(opts \\ []) do
    {source, descriptions} = reference_descriptions()
    catalog = Map.merge(build_catalog(descriptions, opts), build_predefined(descriptions, opts))
    ingredients = list_ingredients()

    {matched, unmatched} =
      Enum.reduce(ingredients, {%{}, []}, fn ing, {matched, unmatched} ->
        case classify(ing.name, catalog, opts) do
          {:matched, key} ->
            {Map.update(matched, key, [ing], &[ing | &1]), unmatched}

          {:unmatched, reason} ->
            {matched, [%{ingredient: ing, reason: reason} | unmatched]}
        end
      end)

    schemas =
      catalog
      |> Map.values()
      |> Enum.map(fn schema ->
        ings = matched |> Map.get(schema.key, []) |> Enum.sort_by(& &1.name)
        Map.merge(schema, %{matched: ings, matched_count: length(ings)})
      end)
      |> Enum.sort_by(&{-&1.matched_count, -&1.reference_count})

    %{
      source: source,
      schemas: schemas,
      unmatched: Enum.sort_by(unmatched, & &1.ingredient.name),
      total_ingredients: length(ingredients),
      matched_count: length(ingredients) - length(unmatched),
      unmatched_count: length(unmatched),
      schema_count: map_size(catalog)
    }
  end

  @doc """
  The structural signature of a parse: the populated dimensions in display
  order. `:error` when no base food was identified (`canonical_food` is blank).
  """
  @spec signature(Result.t()) :: {:ok, [atom()]} | :error
  def signature(%Result{} = result) do
    if present_string?(result.canonical_food) do
      {:ok, for({dim, _label} <- @dimensions, populated?(dim, result), do: dim)}
    else
      :error
    end
  end

  @doc "Human label for a schema's dimension list, e.g. `\"food + processing\"`."
  @spec label([atom()]) :: String.t()
  def label(dimensions), do: Enum.map_join(dimensions, " + ", &dim_label/1)

  # ── Catalog construction ──────────────────────────────────────────────────

  @doc "The predefined schema catalog and the source it was derived from."
  @spec catalog(keyword()) :: {:reference_files | :ingredients, %{String.t() => schema()}}
  def catalog(opts \\ []) do
    {source, descriptions} = reference_descriptions()
    catalog = Map.merge(build_catalog(descriptions, opts), build_predefined(descriptions, opts))
    {source, catalog}
  end

  # A predefined-pattern match wins first; otherwise fall back to the parser
  # signature and require it to be a known derived schema.
  defp classify(name, catalog, opts) do
    case match_predefined(name) do
      {:ok, key} ->
        {:matched, key}

      :none ->
        case parse_signature(name, opts) do
          {:ok, dims} ->
            key = signature_key(dims)
            if Map.has_key?(catalog, key), do: {:matched, key}, else: {:unmatched, "no matching schema"}

          :error ->
            {:unmatched, "unparseable"}
        end
    end
  end

  # One schema per predefined pattern, always present. `reference_count` /
  # examples are drawn from the reference descriptions that fit the template.
  defp build_predefined(descriptions, _opts) do
    Map.new(@predefined_patterns, fn pattern ->
      examples =
        descriptions
        |> Enum.filter(&fits_pattern?(segments(&1), pattern))

      schema = %{
        key: pattern_key(pattern),
        label: pattern.label,
        dimensions: pattern.slots,
        reference_count: length(examples),
        reference_examples: Enum.take(examples, @max_reference_examples),
        matched: [],
        matched_count: 0
      }

      {pattern_key(pattern), schema}
    end)
  end

  defp match_predefined(name) do
    segs = segments(name)

    Enum.find_value(@predefined_patterns, :none, fn pattern ->
      fits_pattern?(segs, pattern) && {:ok, pattern_key(pattern)}
    end)
  end

  defp fits_pattern?([first | _] = segs, %{type: type, slots: slots}),
    do: normalize_segment(first) == type and length(segs) <= length(slots)

  defp fits_pattern?([], _pattern), do: false

  defp pattern_key(%{type: type}), do: "pattern:" <> type

  defp segments(name) do
    name
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_segment(segment), do: segment |> String.trim() |> String.downcase()

  defp build_catalog(descriptions, opts) do
    Enum.reduce(descriptions, %{}, fn desc, acc ->
      case parse_signature(desc, opts) do
        {:ok, dims} ->
          key = signature_key(dims)

          Map.update(acc, key, new_schema(key, dims, desc), fn schema ->
            %{
              schema
              | reference_count: schema.reference_count + 1,
                reference_examples: add_example(schema.reference_examples, desc)
            }
          end)

        :error ->
          acc
      end
    end)
  end

  defp new_schema(key, dims, example) do
    %{
      key: key,
      label: label(dims),
      dimensions: dims,
      reference_count: 1,
      reference_examples: [example],
      matched: [],
      matched_count: 0
    }
  end

  defp add_example(examples, _desc) when length(examples) >= @max_reference_examples, do: examples
  defp add_example(examples, desc), do: examples ++ [desc]

  # Reference descriptions come from the configured JSON datasets when readable,
  # otherwise from the app's own ingredient corpus.
  defp reference_descriptions do
    descriptions =
      @config_key
      |> config_paths()
      |> Enum.filter(&File.exists?/1)
      |> Enum.flat_map(&read_reference_file/1)

    if descriptions == [] do
      {:ingredients, Enum.map(list_ingredients(), & &1.name)}
    else
      {:reference_files, descriptions}
    end
  end

  defp config_paths(key) do
    case Application.get_env(:mehungry, key, []) do
      path when is_binary(path) -> [path]
      paths when is_list(paths) -> paths
      _ -> []
    end
  end

  defp read_reference_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, json} <- Jason.decode(body) do
      @reference_dataset_keys
      |> Enum.flat_map(&Map.get(json, &1, []))
      |> Enum.map(&Map.get(&1, "description"))
      |> Enum.reject(&(&1 in [nil, ""]))
    else
      _ -> []
    end
  end

  # ── Parsing / signature helpers ───────────────────────────────────────────

  defp parse_signature(text, opts) do
    case Pipeline.parse(text, opts) do
      {:ok, result} -> signature(result)
      {:skipped, _} -> :error
    end
  end

  defp signature_key(dims), do: Enum.map_join(dims, "+", &Atom.to_string/1)

  defp dim_label(dim) do
    Enum.find_value(@dimensions, Atom.to_string(dim), fn {d, label} ->
      d == dim && label
    end)
  end

  defp populated?(:canonical_food, r), do: present_string?(r.canonical_food)
  defp populated?(:harvest_stage, r), do: r.harvest_stage not in [nil, :mature]
  defp populated?(:processing, r), do: r.processing not in [nil, []]
  defp populated?(:processing_modifiers, r), do: r.processing_modifiers not in [nil, []]
  defp populated?(:packaging, r), do: r.packaging not in [nil, :na]
  defp populated?(:part, r), do: present_string?(r.part)
  defp populated?(:dismemberment, r), do: present_string?(r.dismemberment)
  defp populated?(:bone_state, r), do: present_string?(r.bone_state)
  defp populated?(:portion, r), do: r.portion not in [nil, []]
  defp populated?(:grade, r), do: present_string?(r.grade)
  defp populated?(:fat, r), do: present_string?(r.fat)

  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  # ── Data access ───────────────────────────────────────────────────────────
  #and not like(i.name, ^"%APPLEBEE'S%")  and not like(i.name, ^"%Archway%") and not like(i.name, ^"%ARBY'S%") and not like(i.name, ^"%BURGER KING%" ) and not like(i.name, ^"%Babyfood%") and (is_nil(i.data_type) VVor i.data_type != ^"Survey (FNDDS)")

  
  defp list_ingredients do
    brand_names = ["APPLEBEE'S", "%Archway%", "ARBY'S", "BURGER KING", "Baby Foods", "Beverage" ,"Archway", "Andrea's", "Babyfood", "MARS SNACKFOOD", "M&M", "CAMPBELL'S", "CHICK-FIL-A","CRACKER BARREL", "CARRABBA'S", "REESE'S", "HERSHEYS", "KIT KAT", "KRACKEL", "McDONALD'S", "Glutino", "Oscar Mayer", "Pillsbury"]
    second_pass = ["Candies", "beverage", "Cake", "Bread", "Bologna", "Bagel", "Biscuit", "Meatball" , "restaurant", "Ice cream", "Gravy", "Baker", "sauce", "Macaroni", "Cookies", "Cereals", "Breakfast", "Bacon", "Snacks", "Muffins", "Crackers", "Cream", "Croissants", "Dessert", "Danish pastry", "Doughnuts", "muffins", "cream", "Frozen novelties", "Frozen yogurts", "Margarine", "dessert", "Noodles", "Pancakes", "Pie", "Puddings", "Restaurant", "Pizza","dressing","Waffles","Bratwurst", "Butter", "Cheese food", "Pasta", "Salami", "Sauce", "Sandwich", "spread", "Sausage", "mixed"]
   ex_set = brand_names ++ second_pass 
    #escaped_names = Enum.map(names, &Regex.escape/1)
    escaped_brands = Enum.map(ex_set, &Regex.escape/1)

    
    # 3. Join the brands AND manually append the uppercase regex rule without escaping it
    uppercase_pattern = "(^|[^a-zA-Z])[A-Z]{2,}([^a-zA-Z]|$)"
    pattern = Enum.join(escaped_brands ++ [uppercase_pattern], "|")

    Repo.all(
      from(i in Ingredient,
        where: not is_nil(i.fdc_id) and i.fdc_id > 0 and not is_nil(i.name) and i.name != "" and fragment("? !~ ?", i.name, ^pattern) and i.data_type != ^"Survey (FNDDS)",
        select: %{id: i.id, name: i.name, data_type: i.data_type, food_class: i.food_class}
      )
    )
  end
end
