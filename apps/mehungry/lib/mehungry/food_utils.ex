defmodule Mehungry.FoodUtils do 
  
  alias Mehungry.Food.RecipeUtils
  alias Mehungry.Food.RecipeIngredient
  
  def calculate_nutrients_for_meal_list(user_meals) do 
    recipes_user_meals = Enum.reduce(user_meals, [], fn x, acc -> 
      x.recipe_user_meals ++ acc
    end)

    recipe_outcome = Enum.map(recipes_user_meals, fn x ->  
      Enum.map(x.recipe.recipe_ingredients, fn y -> 
        %RecipeIngredient{y | quantity: (y.quantity / x.recipe.servings) * x.consume_portions}
      end)
    end)
    flatten_rec_ing_list = List.flatten(recipe_outcome)

    result = RecipeUtils.calculate_nutrition_for_recipe_ingredient(flatten_rec_ing_list)
    result = calculate_recipe_nutrients(result.flat_recipe_nutrients)
  end

  defp calculate_recipe_nutrients(nutrients) do

    rest =
      Enum.filter(nutrients, fn x ->
        Float.round(x.amount, 3) != 0
      end)

    {mufa_all, rest} = get_nutrient_category(rest, "MUFA", "Fatty acids, total monounsaturated")
    {pufa_all, rest} = get_nutrient_category(rest, "PUFA", "Fatty acids, total polyunsaturated")
    {sfa_all, rest} = get_nutrient_category(rest, "SFA", "Fatty acids, total saturated")
    {tfa_all, rest} = get_nutrient_category(rest, "TFA", "Fatty acids, total trans")
    {vitamins, rest} = Enum.split_with(rest, fn x -> String.contains?(x.name, "Vitamin") end)

    vitamins_all =
      case length(vitamins) > 0 do
        true ->
          #%{name: "Vitamins", amount: nil, measurement_unit: nil, children: vitamins}
         nil
        false ->
          nil
      end

    nuts_pre = [mufa_all, pufa_all, sfa_all, tfa_all, vitamins_all]
    nuts_pre = Enum.filter(nuts_pre, fn x -> !is_nil(x) end)

    nuts_pre =
      Enum.map(nuts_pre, fn x ->
        case is_map(x) do
          true ->
            x

          false ->
            Enum.into(x, %{})
        end
      end)

    nutrients = nuts_pre ++ rest
    nutrients = Enum.filter(nutrients, fn x -> !is_nil(x) end)
    energy = Enum.find(nutrients, fn x -> String.contains?(x.name, "Energy") end)
    carb = Enum.find(nutrients, fn x -> String.contains?(x.name, "Carbohydrate") end)
    protein = Enum.find(nutrients, fn x -> String.contains?(x.name, "Protein") end)
    fiber = Enum.find(nutrients, fn x -> String.contains?(x.name, "Fiber") end)
    fat = Enum.find(nutrients, fn x -> String.contains?(x.name, "Total lipid") end)

    primaries = [energy, fat, carb, protein, fiber]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    nutrients = primaries ++ nutrients

    #socket     
    #|> assign(:nutrients, nutrients)
    #|> assign(:primary_size, length(primaries))
    nutrients
  end


  defp get_nutrient_category(nutrients, category_name, category_sum_name) do
    {category, rest} =
      Enum.split_with(nutrients, fn x -> String.contains?(x.name, category_name) end)

    case length(category) > 0 do
      true ->
        {category_total, rest} =
          Enum.split_with(rest, fn x ->
            String.contains?(x.name, category_sum_name)
          end)

        case length(category_total) == 1 do
          true ->
            {Enum.into(Enum.at(category_total, 0), children: category), rest}

          false ->
            {%{
               amount: 111.1,
               measurement_unit: "to be defined",
               children: category,
               name: category_sum_name
             }, rest}
        end

      false ->
        {nil, rest}
    end
  end


end
