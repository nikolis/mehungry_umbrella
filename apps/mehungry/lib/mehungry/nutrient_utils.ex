defmodule Mehungry.NutrientUtils do
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

  # --------------------------------------------------------------------Utilities For Celendar Widget ------------------------------------------------- #

  def merge_nutrients(list) do
    Enum.reduce(list, %{}, fn nutrients_map, acc ->
      Map.merge(acc, nutrients_map, fn _key, v1, v2 ->
        merge_nutrient(v1, v2)
      end)
    end)
  end

  defp merge_nutrient(n1, n2) do
    base = %{
      "name" => n1["name"],
      "measurement_unit" => n1["measurement_unit"],
      "amount" => n1["amount"] + n2["amount"]
    }

    case {n1["children"], n2["children"]} do
      {nil, nil} ->
        base

      {c1, c2} ->
        children =
          (c1 || [])
          |> Enum.concat(c2 || [])
          |> merge_children()

        Map.put(base, "children", children)
    end
  end

  defp merge_children(children) do
    children
    |> Enum.group_by(& &1["name"])
    |> Enum.map(fn {_name, group} ->
      Enum.reduce(group, fn c, acc ->
        %{
          "name" => acc["name"],
          "measurement_unit" => acc["measurement_unit"],
          "amount" => acc["amount"] + c["amount"]
        }
      end)
    end)
  end

  def merge_nutrients(list) do
    Enum.reduce(list, %{}, fn nutrients_map, acc ->
      Map.merge(acc, nutrients_map, fn _key, v1, v2 ->
        merge_nutrient(v1, v2)
      end)
    end)
  end

  defp merge_nutrient(n1, n2) do
    base = %{
      "name" => n1["name"],
      "measurement_unit" => n1["measurement_unit"],
      "amount" => n1["amount"] + n2["amount"]
    }

    case {n1["children"], n2["children"]} do
      {nil, nil} ->
        base

      {c1, c2} ->
        children =
          (c1 || [])
          |> Enum.concat(c2 || [])
          |> merge_children()

        Map.put(base, "children", children)
    end
  end

  defp merge_children(children) do
    children
    |> Enum.group_by(& &1["name"])
    |> Enum.map(fn {_name, group} ->
      Enum.reduce(group, fn c, acc ->
        %{
          "name" => acc["name"],
          "measurement_unit" => acc["measurement_unit"],
          "amount" => acc["amount"] + c["amount"]
        }
      end)
    end)
  end

  def summarize_meals_nutrients(user_meals) do
    result =
      user_meals
      |> Enum.flat_map(fn item ->
        recipe_nutrients =
          item
          |> Map.get(:recipe_user_meals, [])
          |> Enum.map(& &1.recipe_nutrients)

        ingredient_nutrients =
          item
          |> Map.get(:ingredient_user_meals, [])
          |> Enum.flat_map(fn ing ->
            ing.recipe.nutrients
            |> Enum.map(fn n ->
              %{
                n.name => %{
                  "amount" => n.amount,
                  "measurement_unit" => n.measurement_unit.name,
                  "name" => n.name
                }
              }
            end)
          end)

        recipe_nutrients ++ ingredient_nutrients
      end)

    merged = merge_nutrients(result)
    merged
  end
end
