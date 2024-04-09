defmodule MehungryWeb.CreateRecipeLiveTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  defp create_ingredient(_) do
    ingredient = ingredient_fixture()
    %{ingredient: ingredient}
  end

  defp create_measurement_unit(_) do
    measurement_unit = measurement_unit_fixture()
    %{measurement_unit: measurement_unit}
  end

  @create_params_recipe %{servings: 3, title: "Title Recipe", language_name: "En"}
  @invalid_params_recipe %{servings: nil, title: nil, recipe_ingredients: []}

  describe "Create Recipe" do
    setup [:create_ingredient, :register_and_log_in_user, :create_measurement_unit]

    test "Create Recipe Correct", %{
      conn: conn,
      ingredient: ingredient,
      measurement_unit: measurement_unit
    } do
      {:ok, index_live, html} = live(conn, Routes.create_recipe_index_path(conn, :index))

      ingredients = %{
        0 => %{
          ingredient_id: ingredient.id,
          measurement_unit_id: measurement_unit.id,
          quantity: 33
        }
      }

      assert index_live
             |> element("#add_ingredient")
             |> render_click()

      {:ok, _, html} =
        index_live
        |> form(".the_form", recipe: @create_params_recipe)
        |> render_submit(%{recipe: %{"recipe_ingredients" => ingredients}})
        |> follow_redirect(conn, Routes.recipe_browse_index_path(conn, :index))

      assert html =~ "Recipe created succesfully"
    end
  end
end
