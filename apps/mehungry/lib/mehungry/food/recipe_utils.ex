defmodule Mehungry.Food.RecipeUtils do
  alias Mehungry.Food

  def calculate_recipe_nutrition_value(recipe) do
    gram_mu = Enum.at(Food.get_measurement_unit_by_name("grammar"), 0)

    #{grammar_compatible, needs_measurement_unit_conversion} =
      #Enum.split_while(recipe.recipe_ingredients, fn x -> x.measurement_unit_id == gram_mu.id end)

    calculate_nutrition_for_recipe_ingredient(recipe.recipe_ingredients)
  end

  def calculate_nutrition_for_recipe_ingredient(recipe_ingredients) do
    ingredients_with_nutrients_calculated =
      Enum.map(recipe_ingredients, fn x ->
        {Food.get_ingredient_details!(x.ingredient_id), x.measurement_unit, x.quantity}
      end)
      |> Enum.map(fn x ->
        %{
          ingredient_id: elem(x, 0).id,
          ingredient: elem(x, 0).name,
          recipe_amount: elem(x, 2),
          recipe_measurement_unit: elem(x, 1),
          nutrients:
            Enum.map(elem(x, 0).ingredient_nutrients, fn y ->
              %{
                amount: y.amount,
                nutrient_name: y.nutrient.name,
                nutrient_measurement_unit: y.nutrient.measurement_unit
              }
            end)
            |> Enum.sort_by(fn x -> x.nutrient_name end)
        }
      end)
      |> Enum.map(fn x ->
        %{
          recipe_amount: x.recipe_amount,
          ingredient_id: x.ingredient_id,
          ingredient: x.ingredient,
          measurement_unit: x.recipe_measurement_unit.name,
          nutrients: Enum.map(x.nutrients, fn y -> adjust_amount(x.recipe_amount, y) end)
        }
      end)

    nutrient_entries =
      Enum.reduce(ingredients_with_nutrients_calculated, [], fn x, acc -> acc ++ x.nutrients end)
      |> Enum.group_by(& &1.nutrient_name)

    flat_recipe_nutrients =
      Enum.map(nutrient_entries, fn x ->
        %{
          name: elem(x, 0),
          measurement_unit: Enum.at(elem(x, 1), 0).measurement_unit,
          amount: Enum.reduce(elem(x, 1), 0, fn y, acc -> y.amount + acc end)
        }
      end)
      |> Enum.sort_by(& &1.name)

    %{
      flat_recipe_nutrients: flat_recipe_nutrients,
      ingredients: ingredients_with_nutrients_calculated
    }
  end

  def adjust_amount(recipe_amount, nutrient_entry) do
    adjusted_amount = recipe_amount * nutrient_entry.amount / 100.0

    %{
      nutrient_name: nutrient_entry.nutrient_name,
      amount: adjusted_amount,
      measurement_unit: nutrient_entry.nutrient_measurement_unit.name
    }
  end
end
