defmodule MehungryWeb.Api.V1.SearchController do
  @moduledoc """
  Recipe full-text search (spec §8) and USDA-backed ingredient search for adding
  basket items / recipe ingredients (spec §10).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Accounts
  alias Mehungry.Food
  alias Mehungry.FoodData.Usda.SearchClient
  alias MehungryWeb.Api.V1.BlueprintMatch
  alias MehungryWeb.Api.V1.Locale
  alias MehungryWeb.Api.V1.RecipeJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  @doc "GET /api/v1/search?q=…  — recipe search."
  def index(conn, params) do
    query = params["q"] || ""
    lang = language(conn)
    {_q, result} = Food.search_recipe(query, lang)
    recipes = recipes_from(result)

    blueprint = BlueprintMatch.blueprint(conn, params)
    reports = BlueprintMatch.recipe_reports(blueprint, recipes)

    cards =
      Enum.map(recipes, fn recipe ->
        RecipeJSON.card(recipe, BlueprintMatch.block(blueprint, reports, recipe.id))
      end)

    json(conn, data(cards))
  end

  @doc """
  GET /api/v1/ingredients/search?q=onion — ingredient search.

  Two modes selected by `source`:

  - default (`usda`) — USDA-backed search for *creating* a new ingredient /
    basket item (`{fdc_id, description, data_type, brand}`).
  - `source=local` — the app's **existing** ingredients (mirrors the calendar
    meal form's picker, `Food.IngredientSearch.search/3`), each carrying its
    `units` list (`Food.ingredient_unit_options/1`) so the client can build an
    `IngredientUserMeal` the same way the LiveView does.
  """
  def ingredients(conn, %{"q" => q, "source" => "local"} = params) when is_binary(q) and q != "" do
    owner_id = conn.assigns.current_user && conn.assigns.current_user.id
    # Locale-aware exactly like the calendar meal-form picker: in Greek, search
    # the translated ingredient names and return them as `name` (English base-name
    # search otherwise). Reuses the same `Food.IngredientSearch` functions the
    # LiveView picker uses so results never drift. Both branches yield items with
    # `.id`/`.name`, so unit lookup + serialization below are unchanged.
    locale = Locale.resolve(conn, params)

    ingredients =
      case locale do
        "el" -> Food.IngredientSearch.search_in_language(q, "el", owner_id)
        _ -> Food.IngredientSearch.search(q, [], owner_id)
      end

    units_by_id = unit_options_by_id(ingredients, locale)

    blueprint = BlueprintMatch.blueprint(conn, params)
    reports = BlueprintMatch.ingredient_reports(blueprint, ingredients)

    json(
      conn,
      data(
        Enum.map(ingredients, fn ing ->
          local_ingredient(ing, units_by_id, BlueprintMatch.block(blueprint, reports, ing.id))
        end)
      )
    )
  end

  def ingredients(conn, %{"q" => q}) when is_binary(q) and q != "" do
    case SearchClient.search_foods(q) do
      {:ok, foods} ->
        json(conn, data(Enum.map(foods, &usda_food/1)))

      {:error, {:rate_limited, _}} ->
        {:error, :rate_limited}

      {:error, _} ->
        {:error, :bad_request}
    end
  end

  def ingredients(conn, _params), do: json(conn, data([]))

  # Batch the portion lookup across all hits (one query) and append the shared
  # grams option once, so building N ingredients' unit lists is 2 queries, not 2N.
  defp unit_options_by_id(ingredients, locale) do
    ids = Enum.map(ingredients, & &1.id)
    portions_by_id = Food.get_measurement_unit_portions_for_ingredients(ids)

    Map.new(ids, fn id ->
      {id, Food.build_unit_options(Map.get(portions_by_id, id, []), locale)}
    end)
  end

  defp local_ingredient(ingredient, unit_options_by_id, blueprint_match \\ nil) do
    %{
      id: ingredient.id,
      name: ingredient.name,
      units: Enum.map(Map.get(unit_options_by_id, ingredient.id, []), &unit_option/1)
    }
    |> maybe_blueprint_match(blueprint_match)
  end

  defp maybe_blueprint_match(map, nil), do: map
  defp maybe_blueprint_match(map, block), do: Map.put(map, :blueprint_match, block)

  defp unit_option(%{} = o) do
    %{
      unit_selection: o.unit_selection,
      measurement_unit_id: o.measurement_unit_id,
      ingredient_portion_id: o.ingredient_portion_id,
      label: o.label
    }
  end

  defp recipes_from({recipes, _cursor}), do: recipes
  defp recipes_from(recipes) when is_list(recipes), do: recipes
  defp recipes_from(_), do: []

  defp usda_food(food) do
    %{
      fdc_id: Map.get(food, :fdc_id) || food["fdc_id"],
      description: Map.get(food, :description) || food["description"],
      data_type: Map.get(food, :data_type) || food["data_type"],
      brand: Map.get(food, :brand) || food["brand"]
    }
  end

  defp language(conn) do
    case conn.assigns[:current_user] do
      nil -> nil
      user -> Accounts.get_user_language(user.id)
    end
  end
end
