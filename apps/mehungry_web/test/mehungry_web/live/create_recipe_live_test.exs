defmodule MehungryWeb.CreateRecipeLiveTest do
  use MehungryWeb.ConnCase

  alias Mehungry.FoodData.Usda.SeedFileParser
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

    SeedFileParser.get_ingredients_from_food_data_central_json_file(
      "test/foundationDownload.json"
    )

    :ok
  end

  # One `recipe[recipe_ingredients_sort][]` hidden input is rendered per
  # ingredient row, so counting them counts the rows currently in the form.
  defp count_ingredient_rows(html) do
    length(String.split(html, ~s(name="recipe[recipe_ingredients_sort][]"))) - 1
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

      [gram] = Food.search_measurement_unit("gram")

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: gram.id, quantity: 500}
          ]
        })

      recipe = Food.get_recipe!(recipe.id)

      {:ok, index_live, _html} =
        live(conn, Routes.create_recipe_index_path(conn, :edit, recipe.id))

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
    end

    test "Adding an ingredient in edit mode preserves the existing rows (regression)", %{
      conn: conn,
      user: user
    } do
      [ingredient | rest] = Food.search_ingredient("beans", nil)
      [ingredient2 | _rest] = rest
      [gram] = Food.search_measurement_unit("gram")

      recipe =
        Mehungry.FoodFixtures.recipe_fixture(user, %{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: gram.id, quantity: 500},
            %{ingredient_id: ingredient2.id, measurement_unit_id: gram.id, quantity: 250}
          ]
        })

      recipe = Food.get_recipe!(recipe.id)

      {:ok, index_live, html} =
        live(conn, Routes.create_recipe_index_path(conn, :edit, recipe.id))

      # One sort hidden input is rendered per ingredient row, so counting them
      # counts the rows. Both persisted rows are present on load.
      assert count_ingredient_rows(html) == 2

      # Click "Add" with no prior edit — the original bug wiped the existing rows
      # here, leaving a single empty slot. Now the full form is submitted and a
      # new empty row is appended via the sort_param, so the two persisted rows
      # survive and a third (empty) one is appended.
      html =
        index_live
        |> form(".the_form")
        |> render_submit(%{recipe: %{"_action" => "add_ingredient"}})

      assert count_ingredient_rows(html) == 3
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

      # Index mode seeds a single empty ingredient row; fill it and save.
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

      html =
        index_live
        |> form(".the_form", recipe: @invalid_params_recipe)
        |> render_change(%{recipe: %{"recipe_ingredients" => ingredients}})

      assert html =~ "is invalid"
      # stop(index_live)
      {:ok, _index_live, html} = live(conn, Routes.create_recipe_index_path(conn, :index))

      assert html =~ "is invalid"
    end

    test "Review panel lists the real blockers instead of a generic message", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, Routes.create_recipe_index_path(conn, :index))

      # The honest indicator: an incomplete form shows a specific checklist, not
      # a false "ready to save".
      assert html =~ "Before saving, please fix:"
      assert html =~ "Title:"
      refute html =~ "Everything looks good"
    end

    test "Failed save surfaces the specific reason in the flash", %{
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

      # A complete ingredient but a blank required title — the save is rejected
      # and the flash must name the offending field, not a generic message.
      params = Map.put(@create_params_recipe, :title, "")

      html =
        index_live
        |> form(".the_form", recipe: params)
        |> render_submit(%{recipe: %{"recipe_ingredients" => ingredients}})

      assert html =~ "Couldn&#39;t save"
      assert html =~ "Title"
      refute html =~ "Please fix the highlighted fields before saving."
    end

    test "Duplicate title (per user) is rejected with a friendly message", %{
      conn: conn,
      ingredient: ingredient,
      measurement_unit: measurement_unit,
      user: user
    } do
      Mehungry.FoodFixtures.recipe_fixture(user, %{
        title: "Dup Title",
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: measurement_unit.id, quantity: 10}
        ]
      })

      {:ok, index_live, _html} = live(conn, Routes.create_recipe_index_path(conn, :index))

      ingredients = %{
        0 => %{
          ingredient_id: ingredient.id,
          measurement_unit_id: measurement_unit.id,
          quantity: 33
        }
      }

      params = Map.put(@create_params_recipe, :title, "Dup Title")

      html =
        index_live
        |> form(".the_form", recipe: params)
        |> render_submit(%{recipe: %{"recipe_ingredients" => ingredients}})

      assert html =~ "you already have a recipe with this title"
    end
  end
end
