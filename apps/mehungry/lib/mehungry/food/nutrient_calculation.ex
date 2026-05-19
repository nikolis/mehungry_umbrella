defmodule Mehungry.Food.NutrientCalculation do
  alias Mehungry.Food
  alias Mehungry.Food.NutrientNameNormalizer
  alias Mehungry.Food.NutrientHierarchyBuilder

  import Ecto.Query
  alias Mehungry.Repo

  @specific "Energy (Atwater Specific Factors)"
  @general "Energy (Atwater General Factors)"

  def filter_energy_duplicates(nutrients) do
    nutrients
    |> Enum.group_by(& &1.nutrient.reference_id)
    |> Enum.flat_map(fn {_food_id, food_nutrients} ->
      keep_best_energy(food_nutrients)
    end)
  end

  defp keep_best_energy(food_nutrients) do
    {energy_nutrients, other_nutrients} =
      Enum.split_with(food_nutrients, fn nutrient ->
        String.starts_with?(nutrient.nutrient.name, "Energy")
      end)

    selected_energy =
      cond do
        specific = find_energy(energy_nutrients, @specific) ->
          [specific]

        general = find_energy(energy_nutrients, @general) ->
          []

        energy_nutrients != [] ->
          [hd(energy_nutrients)]

        true ->
          []
      end

    other_nutrients ++ selected_energy
  end

  defp find_energy(nutrients, target_name) do
    Enum.find(nutrients, fn nutrient ->
      nutrient.nutrient.name == target_name
    end)
  end

  @doc """
  Main entry point - calculates complete nutrition value for a recipe
  """
  def calculate_recipe_nutrition_value(recipe) do
    recipe_ingredients = get_value(recipe, :recipe_ingredients)

    if is_nil(recipe_ingredients) or recipe_ingredients == [] do
      %{flat_nutrients: [], structured_nutrients: [], total_calories: 0, ingredient_count: 0}
    else
      ingredients = map_ingredients_to_structured_form(recipe_ingredients)
      {8, Map.get(calculate_nutrition_for_recipe(ingredients), :structured_nutrients)}
    end
  end

  def get_value(map, key) do
    get_value_specific(map, key) || get_value_specific(map, Atom.to_string(key))
  end

  def get_value_specific(map, key) when is_atom(key), do: map[key] || map[to_string(key)]
  def get_value_specific(map, key) when is_binary(key), do: map[key] || map[String.to_atom(key)]

  def map_ingredients_to_structured_form(recipe_ingredient_params) do
    gram =
      Repo.one(from m in Mehungry.Food.MeasurementUnit, where: like(m.name, "gram%"), limit: 1)

    ingredient_ids =
      recipe_ingredient_params
      |> Map.values()
      |> Enum.map(&String.to_integer(&1["ingredient_id"]))
      |> Enum.uniq()

    ingredients =
      Repo.all(
        from i in Mehungry.Food.Ingredient,
          where: i.id in ^ingredient_ids,
          preload: [
            :ingredient_portions,
            ingredient_nutrients: [nutrient: :measurement_unit]
          ]
      )

    ingredients_by_id =
      Map.new(ingredients, fn ingredient ->
        {ingredient.id, ingredient}
      end)

    recipe_ingredients_with_nutrients =
      recipe_ingredient_params
      |> Map.values()
      |> Enum.map(fn params ->
        ingredient_id = String.to_integer(params["ingredient_id"])

        ingredient =
          Map.fetch!(ingredients_by_id, ingredient_id)

        gram_weight =
          calculate_gram_weight(
            ingredient,
            get_value(params, :measurement_unit_id),
            get_value(params, :quantity),
            gram
          )

        %{
          quantity: params["quantity"],
          measurement_unit_id: params["measurement_unit_id"],
          ingredient: ingredient,
          nutrients: build_nutrient_list(ingredient, gram_weight),
          gram_weight: gram_weight
        }
      end)
  end

  def calculate_gram_weight(ingredient, measurement_unit_id, quantity, grammar) do
    quantity_float = safe_to_float(quantity)

    portion =
      Enum.find(ingredient.ingredient_portions || [], fn p ->
        p.measurement_unit_id == measurement_unit_id
      end)

    cond do
      portion && portion.gram_weight ->
        quantity_float * portion.gram_weight

      measurement_unit_id == grammar.id ->
        quantity_float

      true ->
        quantity_float
    end
  end

  def safe_to_float(value) when is_float(value), do: value
  def safe_to_float(value) when is_integer(value), do: value * 1.0

  def safe_to_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0.0
    end
  end

  def safe_to_float(_), do: 0.0

  def safe_nutrient_amount(amount) when is_float(amount), do: amount
  def safe_nutrient_amount(amount) when is_integer(amount), do: amount * 1.0
  def safe_nutrient_amount(_), do: 0.0

  def build_nutrient_list(ingredient, gram_weight) do
    gram_weight_float = safe_to_float(gram_weight)
    scaling_factor = gram_weight_float / 100.0

    nutrients = filter_energy_duplicates(ingredient.ingredient_nutrients)

    Enum.map(nutrients, fn nutrient_entry ->
      amount = safe_nutrient_amount(nutrient_entry.amount)
      scaled_amount = amount * scaling_factor

      nutrient_name =
        case nutrient_entry.nutrient do
          %{name: name} when is_binary(name) -> name
          %{name: name} when is_atom(name) -> Atom.to_string(name)
          _ -> "Unknown"
        end

      unit_name =
        case nutrient_entry.nutrient do
          %{measurement_unit: %{name: name}} when is_binary(name) ->
            name

          %{measurement_unit: %{name: name}} when is_atom(name) ->
            Atom.to_string(name)

          %{measurement_unit: %{alternate_name: name}} when is_binary(name) ->
            name

          _ ->
            IO.inspect(nutrient_entry, label: "Nutrient entry")

            "g"
        end

      nutrient_number =
        case nutrient_entry.nutrient do
          %{number: num} when is_binary(num) -> num
          %{number: num} when is_integer(num) -> Integer.to_string(num)
          _ -> nil
        end

      %{
        name: nutrient_name,
        amount: scaled_amount,
        measurement_unit: unit_name,
        nutrient_id: nutrient_entry.nutrient_id,
        nutrient_number: nutrient_number
      }
    end)
  end

  def calculate_nutrition_for_recipe(ingredients_with_nutrients) do
    all_nutrients = Enum.flat_map(ingredients_with_nutrients, & &1.nutrients)

    # Group by normalized name
    grouped_nutrients =
      Enum.reduce(all_nutrients, %{}, fn nutrient, acc ->
        normalized_name = NutrientNameNormalizer.normalize(nutrient.name)

        existing =
          Map.get(acc, normalized_name, %{
            name: normalized_name,
            amount: 0.0,
            measurement_unit: nutrient.measurement_unit,
            nutrient_id: nutrient.nutrient_id,
            children: []
          })

        Map.put(acc, normalized_name, %{
          existing
          | amount: existing.amount + (nutrient.amount || 0.0)
        })
      end)
      |> Map.values()

    # Build hierarchical structure
    structured_nutrients = NutrientHierarchyBuilder.build_hierarchy(grouped_nutrients)

    # Sort by priority
    sorted_nutrients = sort_nutrients_by_priority(structured_nutrients)

    # Calculate total calories
    total_calories = calculate_total_calories(grouped_nutrients)

    %{
      flat_nutrients: grouped_nutrients,
      structured_nutrients: sorted_nutrients,
      total_calories: total_calories,
      ingredient_count: length(ingredients_with_nutrients)
    }
  end

  def sort_nutrients_by_priority(nutrient_map) when is_map(nutrient_map) do
    priority_order = %{
      "Energy" => 1,
      "Protein" => 2,
      "Total Fat" => 3,
      "Vitamins" => 4,
      "carbohydrates" => 5,
      "Fiber" => 6,
      "Total Sugars" => 7,
      "Minerals" => 8
    }

    nutrient_map
    |> Enum.filter(fn {_name, nutrient} -> not is_nil(nutrient) end)
    |> Enum.sort_by(fn {name, _nutrient} ->
      {Map.get(priority_order, name, 999), name}
    end)
    |> Enum.map(fn {_name, nutrient} -> nutrient end)
  end

  def calculate_total_calories(nutrients) do
    energy_nutrient =
      Enum.find(nutrients, fn nutrient ->
        nutrient.name == "Energy"
      end)

    if energy_nutrient do
      Float.round(energy_nutrient.amount, 0)
    else
      0
    end
  end

  def pretty_print_nutrition(nutrition_result) do
    IO.puts("\n" <> String.duplicate("=", 50))
    IO.puts("📊 NUTRITION SUMMARY")
    IO.puts(String.duplicate("=", 50))
    IO.puts("Total Calories: #{Float.round(nutrition_result.total_calories, 0)} kcal")
    IO.puts("Number of Ingredients: #{nutrition_result.ingredient_count}")
    IO.puts("")

    print_nutrients(nutrition_result.structured_nutrients, 0)

    IO.puts(String.duplicate("=", 50))
  end

  defp print_nutrients([], _level), do: :ok

  defp print_nutrients([nutrient | rest], level) do
    indent = String.duplicate("  ", level)
    amount = Float.round(nutrient.amount, 1)
    unit = nutrient.measurement_unit

    IO.puts("#{indent}• #{nutrient.name}: #{amount} #{unit}")

    if nutrient.children && length(nutrient.children) > 0 do
      print_nutrients(nutrient.children, level + 1)
    end

    print_nutrients(rest, level)
  end
end
