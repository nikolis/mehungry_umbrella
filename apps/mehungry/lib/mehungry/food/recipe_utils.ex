defmodule Mehungry.Food.RecipeUtils do
  @moduledoc """
  This is module dedicated to common operations on recipes more specifically related to 
  nutrition analysis regarding recipes and the ingredients involved
  """
  alias Mehungry.Food
  alias Mehungry.Food.Recipe

    @doc """
  Sort nutrients to have on top entries that are relevant to most people
  """
  def sort_nutrients_from_db(nutrients) do
    carb = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Carbohydrate") end)
    protein = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Protein") end)
    fiber = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Fiber") end)
    fat = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Total lipid") end)
    sugar = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Sugar") end)
    energy = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Energy") end)
    vitamins = Enum.find(nutrients, fn {name, _x} -> String.contains?(name, "Vitamins") end)

    primaries = [energy, fat, carb, protein, fiber, sugar, vitamins]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    Enum.with_index(primaries ++ nutrients)
  end

  def get_nutrients(recipe) do
    recipe_nutrients = calculate_recipe_nutrition_value(recipe)
    if is_nil(recipe_nutrients) do
      {recipe_nutrients, []}
    else
      rest =
        Enum.filter(recipe_nutrients.flat_recipe_nutrients, fn x ->
          Float.round(x.amount, 3) != 0
        end)

      # Convert to the format expected by NutrientMerger (atom keys already)
      rest = Enum.map(rest, fn nutrient ->
        %{
          name: nutrient.name,
          amount: nutrient.amount,
          measurement_unit: nutrient.measurement_unit
        }
      end)

      # Merge using NutrientMerger - returns list with atom keys
      merged_rest = Mehungry.Food.NutrientMerger.merge_flat_list(rest)
      
      {nuts_pre, rest_after_pre} = get_nutrients_pre(merged_rest)

      nutrients = nuts_pre ++ rest_after_pre
      nutrients = Enum.filter(nutrients, fn x -> !is_nil(x) end)

      energy = Enum.find(rest_after_pre, fn x -> String.contains?(to_string(x.name), "Energy") end)

      energy = convert_energy_to_calories_if_needed(energy)
      {imp, rest_sorted} = sort_nutrients(nutrients, energy)
      {imp, rest_sorted}
    end
  end

  def get_nutrients_pre(rest) do
    {mufa_all, rest} = get_nutrient_category(rest, "MUFA", "Monounsaturated Fat")
    {pufa_all, rest} = get_nutrient_category(rest, "PUFA", "Polyunsaturated Fat")
    {sfa_all, rest} = get_nutrient_category(rest, "SFA", "Saturated Fat")
    {tfa_all, rest} = get_nutrient_category(rest, "TFA", "Trans Fat")
    {vitamins_all, rest} = get_nutrient_category(rest, "Vitamin", "Vitamins")

    nuts_pre = [mufa_all, vitamins_all, pufa_all, sfa_all, tfa_all]
    nuts_pre = Enum.filter(nuts_pre, fn x -> !is_nil(x) end)

    {nuts_pre, rest}
  end

  @doc """
  Sort nutrients to have on top entries that are relevant to most people
  """
  def sort_nutrients(nutrients, energy) do
    carb = Enum.find(nutrients, fn x -> String.contains?(to_string(x.name), "Carbohydrate") end)
    protein = Enum.find(nutrients, fn x -> String.contains?(to_string(x.name), "Protein") end)
    fiber = Enum.find(nutrients, fn x -> String.contains?(to_string(x.name), "Fiber") end)
    fat = Enum.find(nutrients, fn x -> String.contains?(to_string(x.name), "Total Fat") end)
    sugar = Enum.find(nutrients, fn x -> String.contains?(to_string(x.name), "Sugar") end)

    primaries = [energy, fat, carb, protein, fiber, sugar]
    primaries = Enum.filter(primaries, fn x -> !is_nil(x) end)
    nutrients = Enum.filter(nutrients, fn x -> x not in primaries end)
    {length(primaries), primaries ++ nutrients}
  end

  def convert_energy_to_calories_if_needed(nil), do: nil

  def convert_energy_to_calories_if_needed(energy) do
    case energy.measurement_unit do
      "kilojoule" ->
        %{energy | amount: energy.amount * 0.2390057361, measurement_unit: "kcal"}

      _ ->
        energy
    end
  end

  @doc """
  Given a set of nutrients, category_name(being substring that should be part of the name of all the nutrients belonging in the category) and the name that the aggregating entry should have.

  Returns aggregated category and remaining nutrients.
  """
  def get_nutrient_category(nutrients, category_name, category_sum_name) do
    {category, rest} =
      Enum.split_with(nutrients, fn x -> 
        x && x.name && String.contains?(to_string(x.name), category_name) 
      end)

    if length(category) > 0 do
      # Find if the aggregator exists as an entry in the nutrients
      {category_total, rest_after_total} =
        Enum.split_with(rest, fn x ->
          x && x.name && String.contains?(to_string(x.name), category_sum_name)
        end)

      if length(category_total) == 1 do
        # Use the existing aggregate category
        existing = Enum.at(category_total, 0)
        updated = %{existing | children: category}
        {updated, rest_after_total}
      else
        # Create the aggregating category
        total_amount = Enum.reduce(category, 0, fn x, acc -> x.amount + acc end)
        category_first = Enum.at(category, 0)

        aggregated = %{
          name: category_sum_name,
          amount: total_amount,
          measurement_unit: category_first.measurement_unit,
          children: category
        }
        {aggregated, rest_after_total}
      end
    else
      {nil, rest}
    end
  end

  def calculate_recipe_nutrition_value(recipe) do
    case Map.get(recipe, :recipe_ingredients) do
      nil ->
        map_ingredients_to_structured_form_pre_saved(recipe["recipe_ingredients"])
        |> calculate_nutrition_for_recipe_ingredient()

      _ ->
        map_ingredients_to_structured_form(recipe.recipe_ingredients)
        |> calculate_nutrition_for_recipe_ingredient()
    end
  end

  def map_ingredients_to_structured_form_pre_saved(nil), do: nil

  def map_ingredients_to_structured_form_pre_saved(recipe_ingredients) do
    Enum.map(recipe_ingredients, fn {_, x} ->
      {Food.get_ingredient_details!(x["ingredient_id"]),
       Food.get_measurement_unit!(x["measurement_unit_id"]), x["quantity"]}
    end)
    |> Enum.filter(fn x -> is_nil(elem(x, 0)) == false end)
    |> Enum.map(fn x ->
      %{
        ingredient_id: elem(x, 0).id,
        ingredient: elem(x, 0).name,
        ingredient_item: elem(x, 0),
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
  end

  def reform_nutrients(nutrients) do
    nutrients
    |> Enum.map(fn x ->
      Map.new([
        {x.name,
         %{x | measurement_unit: x.measurement_unit.name}
         |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), v} end)}
      ])
    end)
    |> Enum.reduce(&Map.merge/2)
  end

  def map_ingredients_to_structured_form(recipe_ingredients) do
    Enum.map(recipe_ingredients, fn x ->
      {Food.get_ingredient_details!(x.ingredient_id),
       Food.get_measurement_unit!(x.measurement_unit_id), x.quantity}
    end)
    |> Enum.map(fn x ->
      %{
        ingredient_id: elem(x, 0).id,
        ingredient: elem(x, 0).name,
        ingredient_item: elem(x, 0),
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
  end

  def calculate_nutrition_for_recipe_ingredient(nil), do: nil

  def calculate_nutrition_for_recipe_ingredient(recipe_ingredients) do
    ingredients_with_nutrients_calculated =
      Enum.map(recipe_ingredients, fn x ->
        %{
          recipe_amount: x.recipe_amount,
          ingredient_id: x.ingredient_id,
          ingredient: x.ingredient,
          measurement_unit: x.recipe_measurement_unit.name,
          nutrients:
            Enum.map(x.nutrients, fn y ->
              adjust_amount(x.recipe_amount, y, x.recipe_measurement_unit, x.ingredient_item)
            end)
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

  def calculate_nutrition_for_recipe_ingredient_callendar(recipe_ingredients) do
    ingredients_with_nutrients_calculated =
      Enum.map(recipe_ingredients, fn x ->
        {Food.get_ingredient_details!(x.ingredient_id), x.measurement_unit, x.quantity}
      end)
      |> Enum.map(fn x ->
        %{
          ingredient_id: elem(x, 0).id,
          ingredient: elem(x, 0).name,
          ingredient_item: elem(x, 0),
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
          nutrients:
            Enum.map(x.nutrients, fn y ->
              adjust_amount(x.recipe_amount, y, x.recipe_measurement_unit, x.ingredient_item)
            end)
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

  def adjust_amount(recipe_amount, nutrient_entry, measurement_unit, ingredient_item) do
    portion =
      Enum.find(ingredient_item.ingredient_portions, fn x ->
        x.measurement_unit_id == measurement_unit.id
      end)

    recipe_amount =
      if is_number(recipe_amount) do
        recipe_amount
      else
        {recipe_amount, _} = Integer.parse(recipe_amount)
        recipe_amount
      end

    recipe_amount =
      if is_nil(portion) do
        recipe_amount
      else
        recipe_amount * portion.gram_weight
      end

    adjusted_amount = recipe_amount * nutrient_entry.amount / 100.0

    %{
      nutrient_name: nutrient_entry.nutrient_name,
      amount: adjusted_amount,
      measurement_unit: nutrient_entry.nutrient_measurement_unit.name
    }
  end

  def calculate_recipe_ingredient_categories_array(%Recipe{} = recipe) do
    recipe_ingredients = recipe.recipe_ingredients

    ingredients =
      Enum.map(recipe_ingredients, fn x -> Food.get_ingredient_with_category!(x.ingredient_id) end)

    ingredients_table =
      Enum.map(ingredients, fn x ->
        x.category.name
      end)

    Enum.uniq(ingredients_table)
  end

  def calculate_recipe_ingredient_categories_array(nil) do
    []
  end

  # Helper function to safely convert nutrient names to string for display
  def nutrient_name_to_string(nutrient) do
    case nutrient do
      %{name: name} when is_atom(name) -> Atom.to_string(name)
      %{name: name} when is_binary(name) -> name
      _ -> ""
    end
  end
end
