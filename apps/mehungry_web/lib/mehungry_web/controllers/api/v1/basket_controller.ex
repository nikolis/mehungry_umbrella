defmodule MehungryWeb.Api.V1.BasketController do
  @moduledoc """
  Shopping basket (spec §10): the user's active basket, item CRUD, and importing
  a recipe's or planned meal's ingredients. Backed by `Mehungry.Inventory`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Food
  alias Mehungry.History
  alias Mehungry.Inventory
  alias MehungryWeb.Api.V1.BasketJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def show(conn, _params) do
    basket = Inventory.get_or_create_basket_for_user(uid(conn))
    json(conn, BasketJSON.basket(basket))
  end

  def add_item(conn, params) do
    basket = Inventory.get_or_create_basket_for_user(uid(conn))

    item_params = %{
      name: params["name"],
      quantity: to_float(params["quantity"]),
      measurement_unit_id: params["measurement_unit_id"],
      nutrition: params["nutrition_data"] || %{},
      usda_fdc_id: params["usda_fdc_id"]
    }

    with {:ok, item} <- Inventory.add_item(basket.id, item_params) do
      conn |> put_status(:created) |> json(data(BasketJSON.item(item)))
    end
  end

  def update_item(conn, %{"id" => id} = params) do
    with {:ok, item} <- fetch_owned_item(conn, id),
         {:ok, item} <- Inventory.update_basket_item(item, item_attrs(params)) do
      json(conn, data(BasketJSON.item(item)))
    end
  end

  def delete_item(conn, %{"id" => id}) do
    with {:ok, item} <- fetch_owned_item(conn, id),
         {:ok, _} <- Inventory.delete_basket_item(item) do
      send_resp(conn, :no_content, "")
    end
  end

  def import_recipe(conn, %{"recipe_id" => recipe_id} = params) do
    basket = Inventory.get_or_create_basket_for_user(uid(conn))
    servings = params["servings"] || 1

    with {:ok, recipe} <- fetch_recipe(recipe_id),
         {:ok, _count} <- Inventory.add_items_from_recipe(basket.id, recipe, servings) do
      json(conn, BasketJSON.basket(Inventory.get_shopping_basket!(basket.id)))
    end
  end

  def import_meal(conn, %{"meal_id" => meal_id}) do
    basket = Inventory.get_or_create_basket_for_user(uid(conn))

    with {:ok, meal} <- fetch_meal(conn, meal_id),
         {:ok, _count} <- Inventory.add_items_from_meal(basket.id, meal) do
      json(conn, BasketJSON.basket(Inventory.get_shopping_basket!(basket.id)))
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp item_attrs(params) do
    Map.take(params, ["quantity", "in_storage", "name", "measurement_unit_id"])
  end

  # Ensures the item belongs to one of the caller's baskets.
  defp fetch_owned_item(conn, id) do
    item = Inventory.get_basket_item!(to_int(id))
    basket = Inventory.get_shopping_basket!(item.shopping_basket_id)

    if basket.user_id == uid(conn), do: {:ok, item}, else: {:error, :not_found}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_recipe(id) do
    case Food.get_recipe!(to_int(id)) do
      nil -> {:error, :not_found}
      recipe -> {:ok, recipe}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp fetch_meal(conn, id) do
    {:ok, History.get_user_meal!(uid(conn), to_int(id))}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  defp uid(conn), do: conn.assigns.current_user.id

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  defp to_float(nil), do: 1.0
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v * 1.0
  defp to_float(v) when is_binary(v), do: elem(Float.parse(v), 0)
end
