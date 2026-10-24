defmodule Mehungry.FoodData.UniTools.Decoder do
  @moduledoc """
  Turns a decoded UniTools World Recipes dataset (the whole JSON wrapper map,
  from `Mehungry.FoodData.UniTools.Client`) into the shape the review LiveView
  and `Mehungry.FoodData.UniToolsImporter` consume.

  Unlike MyPlate/Gutenberg — where each ingredient arrives as a free-text line
  that `FoodData.MyPlate.IngredientParser` must split — **UniTools ingredients
  are already structured** (`%{"name" => %{"en" => _}, "quantity" => _, "unit" =>
  _, "note" => _}`). So this decoder builds the normalized ingredient maps that
  `FoodData.RecipeIngredientResolver` documents as its direct input, skipping the
  lossy text round-trip. The resolver is still the shared matching engine.

  `decode/1` returns `%{meta: meta, recipes: [recipe]}`:

    * `meta` — `%{name, version, license, attribution, landing_page}` read from
      the dataset's own wrapper (the licence travels with the data, honouring
      ShareAlike rather than being hardcoded).
    * each `recipe` — `%{index, title, native_name, summary, category, cuisine,
      country, servings, difficulty, prep_minutes, cook_minutes, nutrition,
      ingredients, directions, raw}`, where `ingredients` are
      resolver-ready normalized maps and `directions` is a list of step strings.

  The bilingual (ru/en) source is reduced to **English** (the app ships en/el;
  Russian is dropped). Pure and DB-free.
  """

  @difficulty %{"easy" => 1, "medium" => 2, "hard" => 3}

  @doc "Decodes the dataset wrapper map into `%{meta: meta, recipes: [recipe]}`."
  def decode(%{} = data) do
    cuisines = cuisine_index(Map.get(data, "countries", []))

    recipes =
      data
      |> Map.get("recipes", [])
      |> Enum.with_index(1)
      |> Enum.map(fn {record, index} -> decode_recipe(record, index, cuisines) end)

    %{meta: meta(data), recipes: recipes}
  end

  # ── metadata ────────────────────────────────────────────────────────────────

  defp meta(data) do
    %{
      name: Map.get(data, "name"),
      version: Map.get(data, "version"),
      license: Map.get(data, "license"),
      attribution: Map.get(data, "attribution"),
      landing_page: Map.get(data, "landingPage") || Map.get(data, "homepage")
    }
  end

  # country code ("IT") → English cuisine name ("Italian cuisine").
  defp cuisine_index(countries) when is_list(countries) do
    Map.new(countries, fn c -> {Map.get(c, "code"), en(Map.get(c, "cuisine"))} end)
  end

  defp cuisine_index(_), do: %{}

  # ── per recipe ────────────────────────────────────────────────────────────────

  defp decode_recipe(record, index, cuisines) do
    %{
      index: index,
      title: en(Map.get(record, "name")),
      native_name: Map.get(record, "nativeName"),
      summary: en(Map.get(record, "summary")),
      category: Map.get(record, "category"),
      cuisine: Map.get(cuisines, Map.get(record, "country")),
      country: Map.get(record, "country"),
      servings: int(Map.get(record, "baseServings")),
      difficulty: Map.get(@difficulty, Map.get(record, "difficulty"), 1),
      prep_minutes: int(Map.get(record, "prepMinutes")),
      cook_minutes: int(Map.get(record, "cookMinutes")),
      nutrition: Map.get(record, "nutritionPerServing"),
      ingredients: decode_ingredients(Map.get(record, "ingredients", [])),
      directions: decode_steps(Map.get(record, "steps", [])),
      raw: Jason.encode!(record, pretty: true)
    }
  end

  # Build the normalized maps RecipeIngredientResolver consumes directly. Units
  # pass through lowercased — the resolver canonicalizes aliases (g, kg, tbsp,
  # tsp, clove, slice, piece…); units it can't convert (ml, l, pinch, sprig,
  # toTaste) simply land in the importer's `unmatched` list for the admin to fix.
  defp decode_ingredients(ingredients) when is_list(ingredients) do
    Enum.map(ingredients, fn ing ->
      name = en(Map.get(ing, "name"))
      quantity = num(Map.get(ing, "quantity"))
      unit = normalize_unit(Map.get(ing, "unit"))
      note = en(Map.get(ing, "note"))

      %{
        name: name,
        quantity: quantity,
        unit: unit,
        original: display_line(quantity, Map.get(ing, "unit"), name, note)
      }
    end)
  end

  defp decode_ingredients(_), do: []

  defp decode_steps(steps) when is_list(steps) do
    steps
    |> Enum.map(&en(Map.get(&1, "text")))
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  defp decode_steps(_), do: []

  # Human display text kept as the recipe_ingredient's `ingredient_allias`.
  defp display_line(quantity, unit, name, note) do
    [fmt_qty(quantity), display_unit(unit), name]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> append_note(note)
  end

  defp append_note(line, nil), do: line
  defp append_note(line, ""), do: line
  defp append_note(line, note), do: "#{line} (#{note})"

  # "piece"/"toTaste" read awkwardly in a display line; drop the unit word there
  # (the structured unit is still passed to the resolver separately).
  defp display_unit(nil), do: nil
  defp display_unit("piece"), do: nil
  defp display_unit("toTaste"), do: nil
  defp display_unit(unit), do: unit

  defp fmt_qty(nil), do: nil

  defp fmt_qty(q) when is_float(q) do
    if q == Float.round(q), do: q |> trunc() |> Integer.to_string(), else: Float.to_string(q)
  end

  defp fmt_qty(q), do: to_string(q)

  # ── value coercion ─────────────────────────────────────────────────────────

  defp en(%{} = m), do: Map.get(m, "en")
  defp en(v) when is_binary(v), do: v
  defp en(_), do: nil

  defp normalize_unit(unit) when is_binary(unit), do: String.downcase(String.trim(unit))
  defp normalize_unit(_), do: nil

  defp num(n) when is_integer(n), do: n * 1.0
  defp num(n) when is_float(n), do: n
  defp num(_), do: 1.0

  defp int(n) when is_integer(n), do: n
  defp int(n) when is_float(n), do: trunc(n)
  defp int(_), do: nil
end
