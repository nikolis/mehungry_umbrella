defmodule Mehungry.FoodData.MyPlateImporter do
  @moduledoc """
  Imports USDA MyPlate Kitchen recipes (public domain, via `myplate.food`) into
  the Food context.

  Like `FoodData.SpoonacularImporter`, this is a thin adapter: it fetches a
  recipe, maps the MyPlate JSON into the normalized ingredient shape, and hands
  the matching off to the shared `FoodData.RecipeIngredientResolver`. The one
  MyPlate-specific wrinkle is that ingredients arrive as free text
  (`"1 1/2 cups flour"`) rather than structured fields, so each line is run
  through `FoodData.MyPlate.IngredientParser` first.

  ## Attribution (required)

  MyPlate recipes are public domain, but reuse must credit the source. The
  `contributor` + `source_url` are written into the recipe's `author` /
  `original_url` columns so the credit and a link to the original are preserved.

  ## Nutrition

  MyPlate's own nutrition table is **not** imported. `Food.create_recipe/1`
  recomputes `nutrients`/`badges` from the matched ingredients
  (`RecipePutNutrientsWorker`), keeping these recipes consistent with every other
  recipe in the app.

  ## Return value

  `build_recipe_attrs/2` → `{:ok, attrs, unmatched}` | `{:error, reason}`. The
  `attrs` map is ready to seed the Create Recipe form; the matched ingredients
  carry their `unit_selection` so the form's unit dropdown shows the resolved
  choice, and `unmatched` lists the lines that need manual resolution.
  """

  alias Mehungry.FoodData.MyPlate.IngredientParser
  alias Mehungry.FoodData.RecipeIngredientResolver

  @doc """
  Builds `Recipe.changeset/2`-ready attrs from a MyPlate recipe payload without
  saving. Always returns `{:ok, attrs, unmatched}` — even when nothing matched —
  so the review form can present whatever was resolved (and list the rest for
  the admin to fix by hand).
  """
  def build_recipe_attrs(data, user_id) do
    {resolved, unmatched} =
      data["ingredients"]
      |> List.wrap()
      |> Enum.map(fn ing -> IngredientParser.parse(ing["text"], ing["note"]) end)
      |> RecipeIngredientResolver.resolve_ingredients()

    # Seed each matched ingredient's virtual `unit_selection` from the resolved
    # unit/portion so the Create Recipe form's unit dropdown shows the choice.
    recipe_ingredients = Enum.map(resolved, &put_unit_selection/1)

    attrs = %{
      title: data["name"],
      servings: parse_servings(data["yield"] || data["serving_size"]),
      author: attribution(data),
      original_url: original_url(data),
      # Provenance marker so MyPlate imports can be group-managed (Food.*_by_source).
      source: "myplate",
      image_url: data["image_url"],
      difficulty: 1,
      # MyPlate carries no prep/cook times; the schema requires them, so default
      # to 0 (same as the Spoonacular importer does for missing times).
      cooking_time_lower_limit: 0,
      cooking_time_upper_limit: 0,
      preperation_time_lower_limit: 0,
      preperation_time_upper_limit: 0,
      language_name: "En",
      user_id: user_id,
      private: false,
      description: clean(data["description"]),
      steps: build_steps(data["directions"]),
      recipe_ingredients: recipe_ingredients
    }

    {:ok, attrs, unmatched}
  end

  # Encodes the resolved unit as the form's `unit_selection` (a positive
  # measurement_unit_id, or a negated description-only ingredient_portion_id).
  defp put_unit_selection(%{measurement_unit_id: mu_id} = ri) when is_integer(mu_id),
    do: Map.put(ri, :unit_selection, mu_id)

  defp put_unit_selection(%{ingredient_portion_id: pid} = ri) when is_integer(pid),
    do: Map.put(ri, :unit_selection, -pid)

  defp put_unit_selection(ri), do: ri

  # Prefer the original USDA source link; fall back to the myplate.food page.
  defp original_url(data), do: data["source_url"] || data["recipe_url"] || data["canonical_url"]

  # Attribution line stored in `author`. Public-domain reuse must credit the source.
  defp attribution(data) do
    case data["contributor"] |> to_string() |> String.trim() do
      "" -> "USDA MyPlate Kitchen (public domain)"
      contributor -> contributor <> " — USDA MyPlate (public domain)"
    end
  end

  # "16 servings" / "1" → integer; anything without a number → nil.
  defp parse_servings(nil), do: nil

  defp parse_servings(value) do
    case Regex.run(~r/\d+/, to_string(value)) do
      [n] -> String.to_integer(n)
      _ -> nil
    end
  end

  # MyPlate `directions` is a single paragraph; split into sentence-sized steps.
  defp build_steps(directions) when is_binary(directions) do
    directions
    |> String.split(~r/(?<=[.!?])\s+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map(fn {sentence, index} -> %{index: index, description: sentence} end)
  end

  defp build_steps(_), do: []

  defp clean(nil), do: ""
  defp clean(text), do: text |> String.replace(~r/\s+/, " ") |> String.trim()
end
