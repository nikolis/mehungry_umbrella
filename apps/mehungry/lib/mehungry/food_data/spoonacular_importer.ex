defmodule Mehungry.FoodData.SpoonacularImporter do
  @moduledoc """
  Imports recipes from the Spoonacular API into the Food context.

  The ingredient matching + unit resolution is **not** here — it's the shared,
  source-agnostic `Mehungry.FoodData.RecipeIngredientResolver`. This module only
  fetches from Spoonacular and maps its JSON into the resolver's normalized
  ingredient shape (incl. a gram weight lifted from `measures.metric`).

  ## Return values

  `fetch_for_form/3` returns `{:ok, attrs, unmatched}` where:
  - `attrs`     — ready to pass to `Recipe.changeset/2` / `init/3`
  - `unmatched` — list of `%{name, quantity, unit, original, reason}` maps

  `import_recipe/3` returns `{:ok, %Recipe{}}` or `{:error, reason}`.
  """

  alias Mehungry.Food
  alias Mehungry.FoodData.RecipeIngredientResolver

  @api_base "https://api.spoonacular.com"

  # Spoonacular `measures.metric.unitShort` values treated as grams.
  @gram_units ~w(g gr gram grams grammar)

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

  defp fetch_recipe(_id, api_key) when api_key in [nil, ""], do: {:error, :missing_api_key}

  defp fetch_recipe(id, api_key) do
    query = URI.encode_query(%{"includeNutrition" => "true", "apiKey" => api_key})
    url = "#{@api_base}/recipes/#{id}/information?#{query}"

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

  defp search_recipes(_query, api_key, _number) when api_key in [nil, ""],
    do: {:error, :missing_api_key}

  defp search_recipes(query, api_key, number) do
    qs =
      URI.encode_query(%{"query" => query, "number" => number, "apiKey" => api_key})

    url = "#{@api_base}/recipes/complexSearch?#{qs}"

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
    {recipe_ingredients, unmatched_list} =
      data["extendedIngredients"]
      |> List.wrap()
      |> Enum.map(&normalize_ingredient/1)
      |> RecipeIngredientResolver.resolve_ingredients()

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

  # Maps one Spoonacular `extendedIngredients` entry into the resolver's
  # normalized shape. `metric_grams` lifts Spoonacular's own gram weight from
  # `measures.metric` so the resolver can use it as a last resort.
  defp normalize_ingredient(ing) do
    quantity = to_float(ing["amount"], 1.0)

    %{
      name: ing["name"],
      quantity: quantity,
      unit: ing["unit"],
      original: ing["original"] || "#{quantity} #{ing["unit"]} #{ing["name"]}",
      metric_grams: metric_grams(ing)
    }
  end

  # Spoonacular's `measures.metric` weight, when it's expressed in grams.
  defp metric_grams(ing) do
    metric = get_in(ing, ["measures", "metric"]) || %{}
    amount = to_float(metric["amount"], nil)
    unit = (metric["unitShort"] || "") |> to_string() |> String.trim() |> String.downcase()

    if amount && unit in @gram_units, do: amount, else: nil
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
  # Private helpers
  # ═══════════════════════════════════════════════════════════════════════════

  defp infer_difficulty(nil), do: 1
  defp infer_difficulty(minutes) when minutes <= 30, do: 1
  defp infer_difficulty(minutes) when minutes <= 60, do: 2
  defp infer_difficulty(_), do: 3

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
end
