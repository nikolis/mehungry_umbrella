defmodule MehungryWeb.MyIngredientLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.Food

  setup [:register_and_log_in_user]

  test "new form renders", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/my_ingredients/new")
    assert html =~ "New ingredient"
    assert html =~ "Save Ingredient"
  end

  test "editing your own ingredient renders it", %{conn: conn, user: user} do
    category = category_fixture(%{})

    {:ok, mine} =
      Food.create_user_ingredient(user, %{name: "Mineberry", category_id: category.id})

    {:ok, _view, html} = live(conn, ~p"/my_ingredients/#{mine.id}/edit")
    assert html =~ "Edit ingredient"
    assert html =~ "Mineberry"
  end

  test "editing another user's ingredient is not allowed", %{conn: conn} do
    other = Mehungry.AccountsFixtures.user_fixture()
    category = category_fixture(%{})
    mu = measurement_unit_fixture()

    {:ok, theirs} =
      Food.create_user_ingredient(other, %{
        name: "Notyours",
        category_id: category.id,
        measurement_unit_id: mu.id
      })

    assert_raise Ecto.NoResultsError, fn ->
      live(conn, ~p"/my_ingredients/#{theirs.id}/edit")
    end
  end
end
