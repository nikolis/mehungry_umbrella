defmodule MehungryWeb.Api.V1.BasketTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  test "GET /basket creates and returns an empty active basket", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/basket")
    assert %{"data" => %{"id" => _, "items" => [], "items_count" => 0}} = json_response(conn, 200)
  end

  test "add, update, delete a basket item", %{conn: conn} do
    created =
      conn
      |> post(~p"/api/v1/basket/items", %{"name" => "Eggplant", "quantity" => 2.0})
      |> json_response(201)

    assert %{"data" => %{"id" => item_id, "name" => "Eggplant", "in_storage" => false}} = created

    updated =
      conn
      |> put(~p"/api/v1/basket/items/#{item_id}", %{"in_storage" => true})
      |> json_response(200)

    assert %{"data" => %{"in_storage" => true}} = updated

    assert conn |> delete(~p"/api/v1/basket/items/#{item_id}") |> response(204)
  end

  test "basket items carry a grocery aisle", %{conn: conn} do
    # A catalog ingredient in the "Vegetables" category → classifies to produce;
    # its search_name is derived from the name, which is how add_item resolves it.
    # (`category_fixture` dedups on the misspelled `:catgeory_name` key, so we pass
    # both spellings to force a fresh "Vegetables" category rather than reusing one.)
    _ =
      FoodFixtures.ingredient_fixture(%{
        name: "Broccoli",
        catgeory_name: "Vegetables",
        category_name: "Vegetables"
      })

    produce =
      conn
      |> post(~p"/api/v1/basket/items", %{"name" => "Broccoli", "quantity" => 1.0})
      |> json_response(201)

    assert %{"data" => %{"aisle" => "produce"}} = produce

    # A free-text manual item with no catalog match falls into "other".
    other =
      conn
      |> post(~p"/api/v1/basket/items", %{"name" => "Zzxqv Widget", "quantity" => 1.0})
      |> json_response(201)

    assert %{"data" => %{"aisle" => "other"}} = other

    listed = conn |> get(~p"/api/v1/basket") |> json_response(200)
    assert Enum.all?(listed["data"]["items"], &is_binary(&1["aisle"]))
  end

  test "import a recipe's ingredients into the basket", %{conn: conn, user: user} do
    recipe = FoodFixtures.recipe_fixture(user)

    conn = post(conn, ~p"/api/v1/basket/import/recipe/#{recipe.id}", %{"servings" => 2})
    assert %{"data" => %{"items_count" => count}} = json_response(conn, 200)
    assert count >= 1
  end

  test "cannot update another user's basket item", %{conn: conn} do
    other = Mehungry.AccountsFixtures.user_fixture()
    other_basket = Mehungry.Inventory.get_or_create_basket_for_user(other.id)
    {:ok, item} = Mehungry.Inventory.add_item(other_basket.id, %{name: "Milk", quantity: 1.0, measurement_unit_id: nil, nutrition: %{}, usda_fdc_id: nil})

    assert conn |> put(~p"/api/v1/basket/items/#{item.id}", %{"in_storage" => true}) |> json_response(404)
  end

  test "presign returns 400 when uploads are not configured", %{conn: conn} do
    # aws_bucket is nil in the test env.
    conn = post(conn, ~p"/api/v1/uploads/presign", %{"kind" => "recipe_image", "content_type" => "image/jpeg"})
    assert json_response(conn, 400)
  end
end
