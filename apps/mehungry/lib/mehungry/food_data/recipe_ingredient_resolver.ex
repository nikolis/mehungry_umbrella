defmodule Mehungry.FoodData.RecipeIngredientResolver do
  @moduledoc """
  Source-agnostic engine that turns a list of *normalized* ingredient maps into
  `recipe_ingredients` rows ready for `Recipe.changeset/2`, matched against the
  existing ingredient / measurement-unit / portion data. Shared by every recipe
  importer (`FoodData.SpoonacularImporter`, `FoodData.MyPlateImporter`) so the
  matching policy lives in exactly one place.

  It never creates ingredients, measurement units, categories, or portions.

  ## Input

  Each normalized entry is a map:

      %{
        name: "olive oil",      # ingredient name for the relevance search
        quantity: 0.5,          # numeric amount (defaults to 1.0 if missing)
        unit: "cup",            # unit token ("" / nil → treated as "piece")
        original: "1/2 cup olive oil",   # verbatim display text (→ ingredient_allias)
        metric_grams: nil       # optional last-resort gram weight (float) or nil
      }

  ## Matching policy

  For each entry it:

    1. Ranks candidates with `IngredientSearch.search_relevant/1` — the same
       relevance-filtered resolution the AI recipe agent uses — and considers
       the top few, picking the first that can actually represent the
       measurement (so a whole food with the right portion wins over a
       processed variant that has none). An empty list → `:ingredient_not_found`.
    2. Resolves the unit into something the recipe schema + nutrition engine
       accept, in order of fidelity:
       grams verbatim → deterministic mass conversion (oz/lb/kg/mg) → a USDA
       description-only `IngredientPortion` matching the unit ("cup", "medium",
       "tbsp", carrying a real measured gram weight) → a caller-supplied
       `metric_grams` gram weight. The portion path is what lets cooking/count
       units resolve; USDA ingredients almost never have a unit-bearing portion.

  ## Return value

  `resolve_ingredients/1` returns `{recipe_ingredients, unmatched}` where:
  - `recipe_ingredients` — maps ready to nest under `Recipe.changeset/2`
  - `unmatched` — list of `%{name, quantity, unit, original, reason}` maps,
    `reason` ∈ `:ingredient_not_found | :unit_not_found | :portion_not_found`
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.IngredientPortion
  alias Mehungry.Food.IngredientSearch

  # Unit names treated directly as grams (mirrors NutrientCalculation).
  @gram_unit_names ~w(g gr gram grams grammar)

  # How many relevance-ranked ingredient candidates to try when resolving a unit
  # (#2): lets a whole food that actually has the needed portion win over a
  # higher-ranked processed variant that has none.
  @match_candidates 5

  # Unit name → tokens accepted inside a USDA portion `description`
  # ("1 cup, chopped", "1 medium (2-1/2\" dia)", "1 tbsp chopped"). Matched as
  # whole tokens, so "cup" never matches "cupcake".
  @unit_aliases %{
    "tablespoon" => ~w(tbsp tablespoon),
    "tablespoons" => ~w(tbsp tablespoon),
    "tbsp" => ~w(tbsp tablespoon),
    "tbsps" => ~w(tbsp tablespoon),
    "teaspoon" => ~w(tsp teaspoon),
    "teaspoons" => ~w(tsp teaspoon),
    "tsp" => ~w(tsp teaspoon),
    "cup" => ~w(cup),
    "cups" => ~w(cup),
    "clove" => ~w(clove),
    "cloves" => ~w(clove),
    "slice" => ~w(slice),
    "slices" => ~w(slice),
    "stick" => ~w(stick),
    "sticks" => ~w(stick),
    "wedge" => ~w(wedge),
    "wedges" => ~w(wedge),
    "ring" => ~w(ring),
    "rings" => ~w(ring),
    "fillet" => ~w(fillet),
    "fillets" => ~w(fillet),
    "can" => ~w(can),
    "cans" => ~w(can),
    "small" => ~w(small),
    "medium" => ~w(medium),
    "large" => ~w(large),
    "piece" => ~w(piece medium each whole fruit),
    "pieces" => ~w(piece medium each whole fruit)
  }

  # Deterministic weight-unit → grams (#3), for mass units left un-metricated.
  # Gram-family names are handled earlier by resolve_grams/2.
  @mass_to_grams %{
    "mg" => 0.001,
    "milligram" => 0.001,
    "milligrams" => 0.001,
    "kg" => 1000.0,
    "kilogram" => 1000.0,
    "kilograms" => 1000.0,
    "oz" => 28.3495,
    "ounce" => 28.3495,
    "ounces" => 28.3495,
    "lb" => 453.592,
    "lbs" => 453.592,
    "pound" => 453.592,
    "pounds" => 453.592
  }

  @doc """
  Resolves a list of normalized ingredient maps (see moduledoc) against the DB.

  Returns `{recipe_ingredients, unmatched}`. Entries with a blank `name` are
  skipped entirely (no match attempt, not reported as unmatched).
  """
  def resolve_ingredients(normalized) when is_list(normalized) do
    {matched, unmatched} =
      normalized
      |> Enum.reject(&blank?(entry_name(&1)))
      |> Enum.map(&classify_ingredient/1)
      |> Enum.split_with(&match?({:matched, _}, &1))

    {Enum.map(matched, fn {:matched, ri} -> ri end),
     Enum.map(unmatched, fn {:unmatched, info} -> info end)}
  end

  @doc """
  The ingredient-name relevance gate the resolver leans on, re-exported so
  importers (and tests) can reach it without depending on `IngredientSearch`
  directly.
  """
  def best_match(name), do: IngredientSearch.best_match(name)

  defp entry_name(entry), do: Map.get(entry, :name) || Map.get(entry, "name")

  # Matches a single normalized ingredient to existing DB records and resolves
  # its measurement. See moduledoc for the matching policy.
  defp classify_ingredient(entry) do
    name = normalize_name(entry_name(entry))
    unit_name = normalize_unit(Map.get(entry, :unit) || Map.get(entry, "unit"))
    quantity = to_float(Map.get(entry, :quantity) || Map.get(entry, "quantity"), 1.0)
    original = Map.get(entry, :original) || Map.get(entry, "original")
    metric_grams = to_float(Map.get(entry, :metric_grams) || Map.get(entry, "metric_grams"), nil)

    unmatched_info = %{
      name: name,
      quantity: quantity,
      unit: unit_name,
      original: original || "#{quantity} #{unit_name} #{name}"
    }

    candidates = IngredientSearch.search_relevant(name) |> Enum.take(@match_candidates)

    case resolve_candidates(candidates, unit_name, quantity, metric_grams) do
      {:ok, ingredient, unit_fields, resolved_quantity} ->
        {:matched,
         Map.merge(unit_fields, %{
           quantity: resolved_quantity,
           ingredient_id: ingredient.id,
           ingredient_allias: original
         })}

      {:error, reason} ->
        Logger.info("RecipeIngredientResolver: unmatched \"#{name}\" (#{unit_name}) — #{reason}")
        {:unmatched, Map.put(unmatched_info, :reason, reason)}
    end
  end

  # An empty candidate list means nothing cleared the relevance bar.
  defp resolve_candidates([], _unit, _qty, _metric), do: {:error, :ingredient_not_found}

  defp resolve_candidates([top | _] = candidates, unit_name, quantity, metric_grams) do
    cond do
      # Ingredient-independent conversions — the measurement can't discriminate
      # between candidates, so take the top relevance match.
      res = resolve_grams(unit_name, quantity) -> attach(top, res)
      res = resolve_mass(unit_name, quantity) -> attach(top, res)
      # Count/volume unit: prefer whichever candidate actually has a USDA portion
      # for it (#2 — a whole food over a processed variant with no portions).
      res = first_portion_match(candidates, unit_name, quantity) -> res
      # Last resort: a caller-supplied gram weight on the top match.
      res = resolve_metric_grams(metric_grams) -> attach(top, res)
      true -> {:error, :portion_not_found}
    end
  end

  defp attach(ingredient, {unit_fields, quantity}),
    do: {:ok, ingredient, unit_fields, quantity}

  # 1. Already in grams → the gram MeasurementUnit, quantity as-is.
  defp resolve_grams(unit_name, quantity) do
    if unit_name in @gram_unit_names, do: grams_fields(quantity), else: nil
  end

  # 3. Deterministic mass conversion for weight units left un-metricated.
  defp resolve_mass(unit_name, quantity) do
    case Map.fetch(@mass_to_grams, unit_name) do
      {:ok, factor} -> grams_fields(quantity * factor)
      :error -> nil
    end
  end

  # 4. A caller-supplied gram weight (Spoonacular's `measures.metric`), last resort.
  defp resolve_metric_grams(grams) when is_float(grams) and grams > 0.0, do: grams_fields(grams)
  defp resolve_metric_grams(_), do: nil

  # 2. First candidate with a description-only USDA portion matching the unit.
  #    The portion's own `gram_weight` drives nutrition downstream, so the
  #    amount is kept verbatim (0.5 "cup" × 160 g/cup = 80 g).
  defp first_portion_match(candidates, unit_name, quantity) do
    words = Map.get(@unit_aliases, unit_name, [unit_name])

    Enum.find_value(candidates, fn ingredient ->
      case best_description_portion(ingredient.id, words) do
        nil ->
          nil

        portion ->
          {:ok, ingredient, %{ingredient_portion_id: portion.id, measurement_unit_id: nil},
           quantity}
      end
    end)
  end

  defp best_description_portion(ingredient_id, words) do
    ingredient_portions(ingredient_id)
    |> Enum.filter(&portion_matches?(&1, words))
    # Prefer the most generic label ("cup" over "cup, chopped").
    |> Enum.sort_by(&String.length(&1.description))
    |> List.first()
  end

  # Usable portion (real gram weight, meaningful label) whose description
  # contains one of `words` as a whole token.
  defp portion_matches?(%{gram_weight: gw, description: desc}, words)
       when is_binary(desc) and is_float(gw) and gw > 0.0 do
    IngredientPortion.meaningful_label?(desc) and
      Enum.any?(words, &(&1 in description_tokens(desc)))
  end

  defp portion_matches?(_, _), do: false

  defp description_tokens(desc) do
    desc |> String.downcase() |> String.split(~r/[^a-zα-ω]+/u, trim: true)
  end

  defp ingredient_portions(ingredient_id) do
    Repo.all(
      from p in IngredientPortion,
        where: p.ingredient_id == ^ingredient_id,
        select: %{id: p.id, description: p.description, gram_weight: p.gram_weight}
    )
  end

  # {unit_fields, quantity} for a gram measurement, or nil when the DB somehow
  # has no gram-family MeasurementUnit (seeds vary: "g"/"gram"/"grams").
  defp grams_fields(quantity) do
    case find_gram_unit() do
      {:ok, unit} -> {%{measurement_unit_id: unit.id, ingredient_portion_id: nil}, quantity}
      {:error, _} -> nil
    end
  end

  defp find_gram_unit do
    Enum.find_value(@gram_unit_names, {:error, :unit_not_found}, fn name ->
      case find_measurement_unit(name) do
        {:ok, unit} -> {:ok, unit}
        _ -> nil
      end
    end)
  end

  # Searches MeasurementUnit by name or alternate_name (existing Food function).
  defp find_measurement_unit(name) do
    case Food.get_measurement_unit_by_name(name) do
      [unit | _] -> {:ok, unit}
      [] -> {:error, :unit_not_found}
    end
  end

  defp normalize_name(nil), do: ""

  defp normalize_name(name) do
    name |> String.trim() |> String.downcase() |> String.replace(~r/\s+/, " ")
  end

  defp normalize_unit(nil), do: "piece"
  defp normalize_unit(""), do: "piece"
  defp normalize_unit(unit), do: unit |> String.trim() |> String.downcase()

  defp to_float(value, _default) when is_float(value), do: value
  defp to_float(value, _default) when is_integer(value), do: value * 1.0
  defp to_float(_, default), do: default

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
