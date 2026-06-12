defmodule Mehungry.Apis.SpoonacularImporter do
  @moduledoc """
  Imports recipes from the Spoonacular API into the Food context.

  ## Matching policy

  The importer never creates ingredients, measurement units, categories, or
  ingredient portions.  For each Spoonacular ingredient it attempts:

    1. Find the best-matching ingredient in the DB via `IngredientSearch`.
    2. Find the measurement unit by name/alternate_name in the DB.
    3. Confirm the ingredient has an `IngredientPortion` for that unit
       (gram-family units are always accepted without a portion row).

  If any step fails the ingredient is placed in the `unmatched` list and
  returned to the caller so the user can resolve it manually.

  ## Return values

  `fetch_for_form/3` returns `{:ok, attrs, unmatched}` where:
  - `attrs`     — ready to pass to `Recipe.changeset/2` / `init/3`
  - `unmatched` — list of `%{name, quantity, unit, original, reason}` maps

  `import_recipe/3` returns `{:ok, %Recipe{}}` or `{:error, reason}`.
  """

  require Logger

  import Ecto.Query, only: [from: 2]

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, MeasurementUnit, IngredientPortion}
  alias Mehungry.Food.IngredientSearch

  @api_base "https://api.spoonacular.com"

  # ═══════════════════════════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════════════════════════

  @doc """
  Fetches a single recipe from Spoonacular by its numeric ID and saves it.
  Unmatched ingredients are silently skipped (logged as warnings).

  Returns `{:ok, %Recipe{}}` or `{:error, reason}`.
  """
  def import_recipe(spoonacular_id, user_id, api_key) do
    with {:ok, data} <- fetch_recipe(spoonacular_id, api_key),
         {:ok, attrs, _unmatched} <- build_recipe_attrs(data, user_id) do
      Food.create_recipe(attrs)
    end
  end

  @doc """
  Fetches a recipe and builds form-ready attrs without saving the recipe.
  No DB records are created as a side effect.

  Returns `{:ok, attrs_map, unmatched_list}` or `{:error, reason}`.
  `attrs_map` is ready to pass to `Recipe.changeset/2`.
  Each entry in `unmatched_list` is:
    `%{name: str, quantity: float, unit: str, original: str, reason: atom}`
  where `reason` is one of:
    `:ingredient_not_found` | `:unit_not_found` | `:portion_not_found`
  """
  def fetch_for_form(spoonacular_id, user_id, api_key) do
    with {:ok, data} <- fetch_recipe(spoonacular_id, api_key) do
      build_recipe_attrs(data, user_id)
    end
  end

  @doc """
  Searches Spoonacular for recipes matching `query`.
  Returns `{:ok, [%{"id" => id, "title" => title, "image" => url}]}` or `{:error, reason}`.
  """
  def search(query, api_key, number \\ 10) do
    search_recipes(query, api_key, number)
  end

  @doc """
  Searches Spoonacular for `query` and bulk-imports up to `number` results.
  Sleeps 250 ms between requests. Returns `{imported_count, errors}`.
  """
  def import_by_query(query, user_id, api_key, opts \\ []) do
    number = Keyword.get(opts, :number, 10)

    with {:ok, results} <- search_recipes(query, api_key, number) do
      {oks, errors} =
        results
        |> Enum.map(fn %{"id" => id} ->
          Process.sleep(250)
          import_recipe(id, user_id, api_key)
        end)
        |> Enum.split_with(&match?({:ok, _}, &1))

      {length(oks), errors}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # HTTP
  # ��══════════════════════════════════════════════════════════════════════════

  defp fetch_recipe(id, api_key) do
    url =
      "#{@api_base}/recipes/#{id}/information" <>
        "?includeNutrition=true&apiKey=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %HTTPoison.Response{status_code: 402}} ->
        {:error, :quota_exceeded}

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp search_recipes(query, api_key, number) do
    url =
      "#{@api_base}/recipes/complexSearch" <>
        "?query=#{URI.encode(query)}&number=#{number}&apiKey=#{api_key}"

    case HTTPoison.get(url) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        with {:ok, %{"results" => results}} <- Jason.decode(body) do
          {:ok, results}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, "HTTP #{status}"}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Recipe building
  # ═══════════════════════════════════════════════════════════════════════════

  @doc false
  def build_recipe_attrs(data, user_id) do
    {matched, unmatched} =
      data["extendedIngredients"]
      |> List.wrap()
      |> Enum.reject(&blank?(&1["name"]))
      |> Enum.map(&classify_ingredient/1)
      |> Enum.split_with(&match?({:matched, _}, &1))

    recipe_ingredients = Enum.map(matched, fn {:matched, ri} -> ri end)

    unmatched_list = Enum.map(unmatched, fn {:unmatched, info} -> info end)

    if recipe_ingredients == [] and unmatched_list != [] do
      {:error, "no ingredients could be matched to existing database entries"}
    else
      attrs = %{
        title: data["title"],
        cousine: data["cuisines"] |> List.wrap() |> List.first(),
        servings: data["servings"],
        cooking_time_lower_limit: data["cookingMinutes"] || data["readyInMinutes"] || 0,
        cooking_time_upper_limit: data["cookingMinutes"] || data["readyInMinutes"] || 0,
        preperation_time_lower_limit: data["preparationMinutes"] || 0,
        preperation_time_upper_limit: data["preparationMinutes"] || 0,
        image_url: data["image"],
        original_url: data["sourceUrl"],
        difficulty: infer_difficulty(data["readyInMinutes"]),
        nutrients: extract_nutrients(get_in(data, ["nutrition", "nutrients"]) || []),
        language_name: "En",
        user_id: user_id,
        description: strip_html(data["summary"] || ""),
        steps: build_steps(data["analyzedInstructions"] || []),
        recipe_ingredients: recipe_ingredients
      }

      {:ok, attrs, unmatched_list}
    end
  end

  # Tries to match a single Spoonacular ingredient to existing DB records.
  # Returns {:matched, recipe_ingredient_map} or {:unmatched, info_map}.
  defp classify_ingredient(ing) do
    name = normalize_name(ing["name"])
    unit_name = normalize_unit(ing["unit"])
    quantity = to_float(ing["amount"], 1.0)

    unmatched_info = %{
      name: name,
      quantity: quantity,
      unit: unit_name,
      original: ing["original"] || "#{quantity} #{unit_name} #{name}"
    }

    with {:ok, ingredient} <- find_ingredient(name),
         {:ok, unit} <- find_measurement_unit(unit_name),
         :ok <- check_portion(ingredient, unit) do
      {:matched,
       %{
         quantity: quantity,
         ingredient_id: ingredient.id,
         measurement_unit_id: unit.id,
         ingredient_allias: ing["original"]
       }}
    else
      {:error, reason} ->
        Logger.info("SpoonacularImporter: unmatched \"#{name}\" — #{reason}")
        {:unmatched, Map.put(unmatched_info, :reason, reason)}
    end
  end

  defp build_steps([]), do: []

  defp build_steps([%{"steps" => steps} | _]) do
    Enum.map(steps, fn step ->
      %{index: step["number"], description: step["step"]}
    end)
  end

  defp build_steps(_), do: []

  defp extract_nutrients(nutrients) when is_list(nutrients) do
    Map.new(nutrients, fn %{"name" => name, "amount" => amount, "unit" => unit} ->
      {name, %{amount: amount, unit: unit}}
    end)
  end

  defp extract_nutrients(_), do: %{}

  # ═══════════════════════════════════════════════════════════════════════════
  # DB lookup helpers (read-only — no inserts)
  # ═══════════════════════════════════════════════════════════════════════════

  # Uses IngredientSearch (ranked fuzzy + prefix) and takes the top result.
  defp find_ingredient(name) do
    case IngredientSearch.search(name) do
      [best | _] -> {:ok, best}
      [] -> {:error, :ingredient_not_found}
    end
  end

  # Searches MeasurementUnit by name or alternate_name (existing Food function).
  defp find_measurement_unit(name) do
    case Food.get_measurement_unit_by_name(name) do
      [unit | _] -> {:ok, unit}
      [] -> {:error, :unit_not_found}
    end
  end

  # Gram-family units are handled directly by NutrientCalculation — no portion needed.
  # For all other units an IngredientPortion row must already exist.
  defp check_portion(%Ingredient{} = ingredient, %MeasurementUnit{} = unit) do
    if gram_unit?(unit) do
      :ok
    else
      exists =
        Repo.exists?(
          from p in IngredientPortion,
            where:
              p.ingredient_id == ^ingredient.id and
                p.measurement_unit_id == ^unit.id
        )

      if exists, do: :ok, else: {:error, :portion_not_found}
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # Private helpers
  # ═══════════════════════════════════════════════════════════════════════════

  defp gram_unit?(%MeasurementUnit{name: name, alternate_name: alt}) do
    String.downcase(name || "") in ["g", "gram", "grams", "grammar"] or alt == "g"
  end

  defp infer_difficulty(nil), do: 1
  defp infer_difficulty(minutes) when minutes <= 30, do: 1
  defp infer_difficulty(minutes) when minutes <= 60, do: 2
  defp infer_difficulty(_), do: 3

  defp normalize_name(name) do
    name |> String.trim() |> String.downcase() |> String.replace(~r/\s+/, " ")
  end

  defp normalize_unit(nil), do: "piece"
  defp normalize_unit(""), do: "piece"
  defp normalize_unit(unit), do: unit |> String.trim() |> String.downcase()

  defp strip_html(nil), do: ""

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&nbsp;", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp to_float(value, _default) when is_float(value), do: value
  defp to_float(value, _default) when is_integer(value), do: value * 1.0
  defp to_float(_, default), do: default

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
