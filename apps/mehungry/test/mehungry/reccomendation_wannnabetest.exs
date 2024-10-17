defmodule Mehungry.ReccomendationsTest do
  use Mehungry.DataCase

  alias Mehungry.Reccomendations

  alias Mehungry.Food
  alias Mehungry.TestDataHelpers
  alias Mehungry.Languages

  defp recipe_fixture_local() do
    mu = TestDataHelpers.measurement_unit_fixture()

    ingredient =
      TestDataHelpers.ingredient_fixture(%{name: "ingredient1", category_name: "category1"})

    ingredient2 =
      TestDataHelpers.ingredient_fixture(%{name: "ingredient2", category_name: "category2"})

    ingredient3 =
      TestDataHelpers.ingredient_fixture(%{name: "ingredient3", category_name: "category3"})

    lang = Languages.get_language_by_name("En")
    _lang2 = Languages.get_language_by_name("Gr")

    # TestDataHelpers.user_fixture   
    {:ok, user} =
      Mehungry.Accounts.register_user(%{email: "som@gmail.com", password: "some_demm_password"})

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 2",
      "servings" => 4,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "user_id" => user.id,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        {"0",
         %{"quantity" => 1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id}},
        {"1",
         %{"quantity" => 0.4, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}}
      ]
    }

    error_result = Food.create_recipe(valid_attrs)

    valid_attrs2 = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented4",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        {"0",
         %{"quantity" => 1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id}},
        {"1",
         %{"quantity" => 0.5, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}}
      ]
    }

    {:ok, test_3} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 5",
      "servings" => 4,
      "user_id" => user.id,
      "language_name" => lang.name,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 0.9, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.6, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id}
      ]
    }

    {:ok, test_2} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented4",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id},
        %{"quantity" => 0.5, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}
      ]
    }

    {:ok, recipe_7} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 5",
      "servings" => 4,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "user_id" => user.id,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => "1"}],
      "recipe_ingredients" => [
        %{"quantity" => 0.9, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id},
        %{"quantity" => 0.6, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}
      ]
    }

    {:ok, recipe_8} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 6",
      "servings" => 4,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "user_id" => user.id,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 1.1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id},
        %{"quantity" => 0.4, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}
      ]
    }

    {:ok, recipe_9} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented4",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.5, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id}
      ]
    }

    {:ok, recipe_4} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 5",
      "servings" => 4,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "user_id" => user.id,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 0.9, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.6, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id}
      ]
    }

    {:ok, recipe_5} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 6",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 1.1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.4, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient2.id}
      ]
    }

    {:ok, recipe_6} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.5, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}
      ]
    }

    {:ok, recipe_1} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 2",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 0.9, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.6, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}
      ]
    }

    {:ok, recipe_2} = Food.create_recipe(valid_attrs)

    valid_attrs = %{
      "author" => "Nikolaos Galerakis",
      "cousine" => "Without boarders",
      "description" => "a recipe I just invented 2",
      "servings" => 4,
      "user_id" => user.id,
      "difficulty" => 1,
      "cooking_time_lower_limit" => 5,
      "preperation_time_lower_limit" => 5,
      "language_name" => lang.name,
      "title" => "tst1 gluten-free",
      "steps" => [%{"title" => "dsa", "description" => "asdfasdf gluten-free", "index" => 1}],
      "recipe_ingredients" => [
        %{"quantity" => 1.1, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient.id},
        %{"quantity" => 0.4, "measurement_unit_id" => mu.id, "ingredient_id" => ingredient3.id}
      ]
    }

    {:ok, recipe_3} = Food.create_recipe(valid_attrs)

    {[recipe_1, recipe_2, recipe_3, recipe_4, recipe_5, recipe_6, recipe_7, recipe_8, recipe_9],
     [test_2, test_3]}
  end

  describe "test reccomender functions" do
    test "Test the actuall reallife capabilities" do
      {recipes, test_set} = recipe_fixture_local()

      recipes_with_index = Enum.with_index(recipes)

      grades =
        Enum.map(recipes_with_index, fn {_x, index} ->
          cond do
            index < 3 ->
              10

            index < 6 ->
              5

            true ->
              0
          end
        end)

      result = Reccomendations.create_reccomender_model(recipes, grades)

      xs =
        Enum.map(result, fn x ->
          x = [1] ++ x
          Numexy.new(x)
        end)

      {thetas, _error} = Reccomendations.optimize_thetas([0, 0, 0, 0], xs, grades, 1_500_000)
      xs = Reccomendations.get_feature_vector(test_set, ["category1", "category2", "category3"])

      Enum.each(xs, fn x ->
        x = [1] ++ x
        _result = Reccomendations.get_grade(thetas, x)
      end)
    end

    test "test the whole linear regression model" do
      xs = [
        Numexy.new([1, 0, 15, 15]),
        Numexy.new([1, 0, 15, 15]),
        Numexy.new([1, 0, 15, 15]),
        Numexy.new([1, 15, 15, 0]),
        Numexy.new([1, 15, 15, 0]),
        Numexy.new([1, 15, 15, 0]),
        Numexy.new([1, 0, 15, 0]),
        Numexy.new([1, 0, 15, 0]),
        Numexy.new([1, 0, 15, 0])
      ]

      ys = [2, 2, 2, 5, 5, 5, 0, 0, 0]
      _result = Reccomendations.optimize_thetas([0, 0, 0, 0], xs, ys, 150)
    end

    test "test sum of errors" do
      xs = [Numexy.new([3, 2, 1]), Numexy.new([3, 2, 1]), Numexy.new([3, 2, 1])]
      thetas = Numexy.new([1, 2, 3])
      ys = [5, 5, 5]
      summ_of_errors = Reccomendations.calculate_sum_error_term(thetas, xs, ys)
      assert summ_of_errors == 15
    end

    test "test_calculate_error_term" do
      theta = Numexy.new([0, 5, 0])
      attrs = Numexy.new([1, 0.99, 0])
      y = 10
      _result = Reccomendations.calculate_error_term(theta, attrs, y)
      # assert result == 5
    end

    def test_something() do
      _food_a_1 = %{name: "food_a_1", at_a: 0, at_b: 15, at_c: 15}
      _food_a_2 = %{name: "food_a_2", at_a: 0, at_b: 15, at_c: 15}
      food_a_3 = %{name: "food_a_3", at_a: 0, at_b: 15, at_c: 15}

      _food_b_1 = %{name: "food_b_1", at_a: 15, at_b: 15, at_c: 0}
      _food_b_2 = %{name: "food_b_2", at_a: 15, at_b: 15, at_c: 0}
      food_b_3 = %{name: "food_b_3", at_a: 15, at_b: 15, at_c: 0}

      _food_c_1 = %{name: "food_c_1", at_a: 0, at_b: 15, at_c: 0}
      _food_c_2 = %{name: "food_c_2", at_a: 0, at_b: 15, at_c: 0}
      food_c_3 = %{name: "food_c_3", at_a: 0, at_b: 15, at_c: 0}

      _food_d_1 = %{name: "food_d_1", at_a: 15, at_b: 0, at_c: 15}
      _food_d_2 = %{name: "food_d_2", at_a: 15, at_b: 0, at_c: 15}
      food_d_3 = %{name: "food_d_3", at_a: 15, at_b: 0, at_c: 15}

      _user_a = [
        %{name: "food_a_1", rating: 10},
        %{name: "food_a_2", rating: 9},
        %{name: "food_b_1", rating: 5},
        %{name: "food_b_2", rating: 5},
        %{name: "food_c_1", rating: 10},
        %{name: "food_c_1", rating: 10},
        %{name: "food_d_1", rating: 0},
        %{name: "food_d_2", rating: 0}
      ]

      _reccomendation_on = [food_a_3, food_b_3, food_c_3, food_d_3]

      # result = Reccomendations.reccomend()
    end
  end
end
