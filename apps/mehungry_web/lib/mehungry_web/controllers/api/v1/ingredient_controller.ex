defmodule MehungryWeb.Api.V1.IngredientController do
  @moduledoc """
  "My ingredients" — the user's custom ingredients (spec §6 `/me/ingredients`).
  Backed by `Food.{list_user_ingredients,create_user_ingredient,
  get_user_ingredient!,update_ingredient,delete_ingredient}`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Food
  alias MehungryWeb.Api.V1.BlueprintMatch

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, params) do
    ingredients = Food.list_user_ingredients(conn.assigns.current_user)
    blueprint = BlueprintMatch.blueprint(conn, params)
    reports = BlueprintMatch.ingredient_reports(blueprint, ingredients)

    json(
      conn,
      data(
        Enum.map(ingredients, fn ing ->
          ingredient_json(ing, BlueprintMatch.block(blueprint, reports, ing.id))
        end)
      )
    )
  end

  def create(conn, %{"ingredient" => attrs} = params) do
    with {:ok, ingredient} <- Food.create_user_ingredient(conn.assigns.current_user, attrs) do
      conn |> put_status(:created) |> json(data(ingredient_json(ingredient, match(conn, params, ingredient))))
    end
  end

  def create(conn, attrs) when is_map(attrs), do: create(conn, %{"ingredient" => attrs})

  def update(conn, %{"id" => id} = params) do
    attrs = params["ingredient"] || Map.drop(params, ["id"])

    with {:ok, ingredient} <- fetch_owned(conn, id),
         {:ok, ingredient} <- Food.update_ingredient(ingredient, attrs) do
      json(conn, data(ingredient_json(ingredient, match(conn, params, ingredient))))
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, ingredient} <- fetch_owned(conn, id),
         {:ok, _} <- Food.delete_ingredient(ingredient) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_owned(conn, id) do
    {:ok, Food.get_user_ingredient!(conn.assigns.current_user, id)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  # Optional `?blueprint_slug=` enrichment for a single ingredient.
  defp match(conn, params, ingredient) do
    blueprint = BlueprintMatch.blueprint(conn, params)
    reports = BlueprintMatch.ingredient_reports(blueprint, [ingredient])
    BlueprintMatch.block(blueprint, reports, ingredient.id)
  end

  defp ingredient_json(ingredient, blueprint_match \\ nil) do
    %{
      id: ingredient.id,
      name: ingredient.name,
      description: ingredient.description,
      category_id: ingredient.category_id,
      measurement_unit_id: ingredient.measurement_unit_id,
      fdc_id: ingredient.fdc_id
    }
    |> maybe_blueprint_match(blueprint_match)
  end

  defp maybe_blueprint_match(map, nil), do: map
  defp maybe_blueprint_match(map, block), do: Map.put(map, :blueprint_match, block)
end
