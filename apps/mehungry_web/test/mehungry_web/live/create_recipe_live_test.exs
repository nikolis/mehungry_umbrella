defmodule MehungryWeb.CreateRecipeLiveTest do
  use MehungryWeb.ConnCase

  alias Mehungry.FdcFoodParser
  alias Mehungry.Food

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Mehungry.Repo)
    # we are setting :auto here so that the data persists for all tests,
    # normally (with :shared mode) every process runs in a transaction
    # and rolls back when it exits. setup_all runs in a distinct process
    # from each test so the data doesn't exist for each test.
    Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, :auto)

    FdcFoodParser.get_ingredients_from_food_data_central_json_file("test/foundationDownload.json")
    :ok
  end

  defp create_ingredient(_) do
    ingredient = ingredient_fixture()
    %{ingredient: ingredient}
  end

  defp create_measurement_unit(_) do
    measurement_unit = measurement_unit_fixture()
    %{measurement_unit: measurement_unit}
  end

  @create_params_recipe %{
    servings: 3,
    title: "Title Recipe",
    language_name: "En",
    difficulty: "1",
    cooking_time_lower_limit: 5,
    preperation_time_lower_limit: 5
  }

  @invalid_params_recipe %{
    servings: "adsf",
    title: "Title Recipe",
    language_name: "En",
    difficulty: "1",
    cooking_time_lower_limit: 5,
    preperation_time_lower_limit: 5
  }

  describe "Create Recipe" do
    setup [:create_ingredient, :register_and_log_in_user, :create_measurement_unit]

    test "Update Recipe Correct update recipe ingredient", %{
      conn: conn,
      ingredient: _ingredient,
      measurement_unit: measurement_unit,
      user: user
    } do
      [ingredient | rest] = Food.search_ingredient("beans", nil)
      [ingredient2 | _rest] = rest

      [grammar] = Food.search_measurement_unit("grammar")

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: grammar.id, quantity: 500}
          ]
        })

      recipe = Food.get_recipe!(recipe.id)

      {:ok, index_live, _html} =
        live(conn, Routes.create_recipe_index_path(conn, :edit, recipe.id))

      old_ingredients = recipe.recipe_ingredients

      ingredients = %{
        0 => %{
          ingredient_id: ingredient2.id,
          measurement_unit_id: measurement_unit.id,
          quantity: 500
        }
      }

      {:ok, _profile_view, _html} =
        index_live
        |> form(".the_form", recipe: @create_params_recipe)
        |> render_submit(%{recipe: %{"recipe_ingredients" => ingredients}})
        |> follow_redirect(conn, Routes.profile_index_path(conn, :index))

      recipe = Mehungry.Food.get_recipe!(recipe.id)
      {recipe_ingredient, _} = List.pop_at(recipe.recipe_ingredients, 0)

      assert recipe_ingredient.ingredient_id == ingredient2.id

      [old_ingredient] = old_ingredients
      assert ingredient.id != old_ingredient.id
    end

    test "Create Recipe Correct", %{
      conn: conn,
      ingredient: ingredient,
      measurement_unit: measurement_unit
    } do
      {:ok, index_live, _html} = live(conn, Routes.create_recipe_index_path(conn, :index))

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
        |> follow_redirect(conn, Routes.profile_index_path(conn, :index))

      assert html =~ "Recipe created succesfully"
    end

    test "Create Recipe Invalid", %{
      conn: conn,
      ingredient: ingredient,
      measurement_unit: measurement_unit
    } do
      # , items: [%{id: 1, name: "easy"}]))
      {:ok, index_live, _html} = live(conn, Routes.create_recipe_index_path(conn, :index))

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

      html =
        index_live
        |> form(".the_form", recipe: @invalid_params_recipe)
        |> render_change(%{recipe: %{"recipe_ingredients" => ingredients}})

      assert html =~ "is invalid"
    end

    test "Create Recipe Invalid maintain state", %{
      conn: conn,
      ingredient: ingredient,
      measurement_unit: measurement_unit
    } do
      # , items: [%{id: 1, name: "easy"}]))
      {:ok, index_live, _html} = live(conn, Routes.create_recipe_index_path(conn, :index))

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

      html =
        index_live
        |> form(".the_form", recipe: @invalid_params_recipe)
        |> render_change(%{recipe: %{"recipe_ingredients" => ingredients}})

      assert html =~ "is invalid"
      # stop(index_live)
      {:ok, _index_live, html} = live(conn, Routes.create_recipe_index_path(conn, :index))

      assert html =~ "is invalid"
    end
  end
end
