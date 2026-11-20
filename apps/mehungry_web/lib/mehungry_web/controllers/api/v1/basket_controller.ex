defmodule MehungryWeb.Api.V1.BasketController do
  @moduledoc """
  Shopping basket (spec §10): the user's active basket, item CRUD, and importing
  a recipe's or planned meal's ingredients. Backed by `Mehungry.Inventory`.

  Every action works on the caller's own active basket by default. Passing
  `basket_id` (or `GET /baskets/:id`) targets any basket the caller **owns or is
  a member of** — that is how a shared list is read and edited. Sharing itself
  (invitations, members) is `BasketSharingController`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Food
  alias Mehungry.History
  alias Mehungry.Inventory
  alias MehungryWeb.Api.V1.BasketJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, _params) do
    baskets = Inventory.list_shopping_baskets_for_user(uid(conn))
    json(conn, data(Enum.map(baskets, &BasketJSON.summary(&1, uid(conn)))))
  end

  def show(conn, params) do
    with {:ok, basket} <- fetch_basket(conn, params["id"] || params["basket_id"]) do
      json(conn, render_basket(conn, basket))
    end
  end

  def add_item(conn, params) do
    with {:ok, basket} <- fetch_basket(conn, params["basket_id"]) do
      do_add_item(conn, basket, params)
    end
  end

  defp do_add_item(conn, basket, params) do
    item_params = %{
      added_by_id: uid(conn),
      name: params["name"],
      quantity: to_float(params["quantity"]),
      measurement_unit_id: params["measurement_unit_id"],
      nutrition: params["nutrition_data"] || %{},
      usda_fdc_id: params["usda_fdc_id"]
    }

    with {:ok, item} <- Inventory.add_item(basket.id, item_params) do
      conn |> put_status(:created) |> json(data(BasketJSON.item(item, aisle_of(item))))
    end
  end

  def update_item(conn, %{"id" => id} = params) do
    with {:ok, item} <- fetch_owned_item(conn, id),
         {:ok, item} <- Inventory.update_basket_item(item, item_attrs(params), uid(conn)) do
      json(conn, data(BasketJSON.item(item, aisle_of(item))))
    end
  end

  def delete_item(conn, %{"id" => id}) do
    with {:ok, item} <- fetch_owned_item(conn, id),
         {:ok, _} <- Inventory.delete_basket_item(item) do
      send_resp(conn, :no_content, "")
    end
  end

  def import_recipe(conn, %{"recipe_id" => recipe_id} = params) do
    servings = params["servings"] || 1

    with {:ok, basket} <- fetch_basket(conn, params["basket_id"]),
         {:ok, recipe} <- fetch_recipe(recipe_id),
         {:ok, _count} <-
           Inventory.add_items_from_recipe(basket.id, recipe, servings, uid(conn)) do
      json(conn, render_basket(conn, Inventory.get_shopping_basket!(basket.id)))
    end
  end

  def import_meal(conn, %{"meal_id" => meal_id} = params) do
    with {:ok, basket} <- fetch_basket(conn, params["basket_id"]),
         {:ok, meal} <- fetch_meal(conn, meal_id),
         {:ok, _count} <- Inventory.add_items_from_meal(basket.id, meal, uid(conn)) do
      json(conn, render_basket(conn, Inventory.get_shopping_basket!(basket.id)))
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────

  # Serializes a basket with a resolved grocery aisle per item (spec §10).
  defp render_basket(conn, basket) do
    aisles = Inventory.aisle_for_items(loaded_items(basket))
    BasketJSON.basket(basket, aisles, uid(conn))
  end

  # No id → the caller's own active basket (created on first use). With an id →
  # that basket, when the caller owns it or is a member; otherwise 404.
  defp fetch_basket(conn, nil), do: {:ok, Inventory.get_or_create_basket_for_user(uid(conn))}

  defp fetch_basket(conn, id) do
    with {:ok, int_id} <- parse_id(id),
         %{} = basket <- Inventory.get_accessible_basket(uid(conn), int_id) do
      {:ok, basket}
    else
      _ -> {:error, :not_found}
    end
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int_id, ""} -> {:ok, int_id}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp aisle_of(item) do
    [item] |> Inventory.aisle_for_items() |> Map.get(item.id, "other")
  end

  defp loaded_items(%{basket_items: items}) when is_list(items), do: items
  defp loaded_items(_), do: []

  defp item_attrs(params) do
    Map.take(params, ["quantity", "in_storage", "name", "measurement_unit_id"])
  end

  # Ensures the item belongs to a basket the caller owns or is a member of.
  defp fetch_owned_item(conn, id) do
    item = Inventory.get_basket_item!(to_int(id))

    if Inventory.can_access_basket?(uid(conn), item.shopping_basket_id),
      do: {:ok, item},
      else: {:error, :not_found}
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
