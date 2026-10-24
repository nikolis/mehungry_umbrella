defmodule Mehungry.FoodData.UniToolsImporter do
  @moduledoc """
  Imports recipes from the **UniTools World Recipes** dataset (501 recipes from
  127 countries; see `Mehungry.FoodData.UniTools.Catalog`) into the Food context.

  Like the MyPlate/Gutenberg importers this is a thin adapter over the shared
  `FoodData.RecipeIngredientResolver`. The difference is the input is already
  structured: `FoodData.UniTools.Decoder` produces resolver-ready normalized
  ingredient maps, so there is no free-text parsing step — the maps go straight
  to the resolver.

  ## Licensing (CC BY-SA 4.0 — not public domain)

  Unlike MyPlate/Gutenberg, UniTools recipes carry a reuse obligation. Each
  imported recipe is stamped with:

    * `author`      — the UniTools credit + licence (shown as the Steps-tab "Source")
    * `original_url`— the dataset landing page
    * `license`     — the licence string (e.g. "CC BY-SA 4.0"), rendered as a
                      visible notice next to the source credit. ShareAlike
                      requires the licence to travel with the adapted recipe.

  The licence/attribution/landing page come from the dataset's own wrapper
  metadata (`meta`), not hardcoded, so an upstream licence change is honoured.

  ## Photos

  **Not imported.** UniTools photos are Wikimedia Commons images under a wide mix
  of per-image licences (GFDL, KOGL, assorted CC variants); rather than vet each,
  `image_url` is left nil and the app's own cover-image generation / manual
  upload fills it in.

  ## Nutrition

  UniTools' per-serving nutrition is discarded; `Food.create_recipe/1` recomputes
  `nutrients`/`badges` from the matched ingredients (`RecipePutNutrientsWorker`),
  keeping these recipes consistent with the rest of the app.

  ## Return value

  `build_recipe_attrs/3` → `{:ok, attrs, unmatched}` — always `:ok` (even with
  zero matches) so the review form can present whatever was resolved and list the
  rest for the admin to fix.
  """

  alias Mehungry.FoodData.RecipeIngredientResolver

  @doc """
  Builds `Recipe.changeset/2`-ready attrs from one decoded UniTools `recipe`
  (`FoodData.UniTools.Decoder`) and the dataset `meta` (licence/attribution),
  without saving.
  """
  def build_recipe_attrs(recipe, meta, user_id) do
    {resolved, unmatched} =
      recipe.ingredients
      |> List.wrap()
      |> RecipeIngredientResolver.resolve_ingredients()

    # Seed each matched ingredient's virtual `unit_selection` so the review
    # form's unit dropdown shows the resolved choice (same as the other importers).
    recipe_ingredients = Enum.map(resolved, &put_unit_selection/1)

    attrs = %{
      title: recipe.title,
      author: attribution(meta),
      original_url: meta.landing_page,
      # Provenance marker so UniTools imports can be group-managed (Food.*_by_source).
      source: "unitools",
      # Content licence travels with the recipe (CC BY-SA 4.0 ShareAlike).
      license: meta.license,
      difficulty: recipe.difficulty || 1,
      # Real times from the dataset (0 when absent; the schema requires them).
      cooking_time_lower_limit: recipe.cook_minutes || 0,
      cooking_time_upper_limit: recipe.cook_minutes || 0,
      preperation_time_lower_limit: recipe.prep_minutes || 0,
      preperation_time_upper_limit: recipe.prep_minutes || 0,
      servings: recipe.servings,
      cousine: recipe.cuisine,
      language_name: "En",
      user_id: user_id,
      # Staged private: imports are curated before going public. The admin flips
      # this in the review form via "Publish on save".
      private: true,
      description: description(recipe, meta),
      steps: build_steps(recipe.directions),
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

  # Summary + native-name note + a credit line carrying the licence.
  defp description(recipe, meta) do
    [recipe.summary, native_note(recipe), credit(meta)]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" — ")
  end

  defp native_note(%{native_name: native, title: title})
       when is_binary(native) and native != "" and native != title,
       do: "Known natively as “#{native}”."

  defp native_note(_), do: nil

  defp credit(meta) do
    "From #{meta.name || "UniTools World Recipes"} — #{attribution(meta)}."
  end

  defp attribution(meta) do
    case {meta.attribution, meta.license} do
      {nil, _} -> "UniTools — theunitools.com"
      {attr, nil} -> attr
      {attr, license} -> "#{attr} (#{license})"
    end
  end

  # UniTools steps are already discrete — one step per directions entry (no
  # sentence splitting, unlike the prose-based Gutenberg/MyPlate importers).
  defp build_steps(directions) when is_list(directions) do
    directions
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map(fn {text, index} -> %{index: index, description: text} end)
  end

  defp build_steps(_), do: []
end
