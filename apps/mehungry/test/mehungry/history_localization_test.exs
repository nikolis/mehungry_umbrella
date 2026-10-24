defmodule Mehungry.HistoryLocalizationTest do
  @moduledoc """
  `format_user_meals/2` localization: ingredient display names, measurement-unit
  labels, and recipe titles are swapped to the viewer's locale when a translation
  exists, and fall back to the source names when it doesn't. This is the single
  view-model the calendar grid and the shareable weekly PNG both read.
  """
  use Mehungry.DataCase

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.History
  alias Mehungry.Food.{IngredientTranslation, MeasurementUnitTranslation}
  alias Mehungry.AI.Bot.RecipeTranslation

  setup do
    for code <- ["el", "Gr"] do
      unless Mehungry.Languages.get_language_by_name(code) do
        {:ok, _} = Mehungry.Languages.create_language(%{name: code})
      end
    end

    :ok
  end

  defp ingredient_meal(user, ingredient, unit) do
    {:ok, meal} =
      History.create_user_meal(%{
        user_id: user.id,
        title: "t",
        meal_type: "breakfast",
        start_dt: ~N[2026-10-06 08:00:00],
        end_dt: ~N[2026-10-06 08:30:00],
        ingredient_user_meals: [
          %{ingredient_id: ingredient.id, measurement_unit_id: unit.id, quantity: 2.0}
        ]
      })

    meal
  end

  test "localizes ingredient name, unit label, and recipe title to the locale" do
    user = user_fixture()

    recipe = recipe_fixture(user, %{title: "Pasta"})

    {:ok, _} =
      %RecipeTranslation{}
      |> RecipeTranslation.changeset(%{recipe_id: recipe.id, language_name: "el", title: "Ζυμαρικά"})
      |> Repo.insert()

    ingredient = ingredient_fixture(%{name: "Banana"})
    unit = measurement_unit_fixture(%{name: "grams"})

    {:ok, _} =
      %IngredientTranslation{}
      |> IngredientTranslation.changeset(%{
        ingredient_id: ingredient.id,
        language_name: "el",
        name: "Μπανάνα"
      })
      |> Repo.insert()

    {:ok, _} =
      %MeasurementUnitTranslation{}
      |> MeasurementUnitTranslation.changeset(%{
        measurement_unit_id: unit.id,
        language_name: "el",
        name: "γραμμάρια"
      })
      |> Repo.insert()

    {:ok, _recipe_meal} =
      History.create_user_meal(%{
        user_id: user.id,
        title: "t2",
        meal_type: "lunch",
        start_dt: ~N[2026-10-06 13:00:00],
        end_dt: ~N[2026-10-06 13:30:00],
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
      })

    _ = ingredient_meal(user, ingredient, unit)

    meals = History.list_calendar_user_meals(user.id, ~D[2026-10-06], ~D[2026-10-06])

    # English (default) keeps the source names.
    en = History.format_user_meals(meals)
    assert ingredient_title(en) == "Banana"
    assert ingredient_unit(en) == "grams"
    assert recipe_title(en) == "Pasta"

    # Greek swaps all three.
    el = History.format_user_meals(meals, "el")
    assert ingredient_title(el) == "Μπανάνα"
    assert ingredient_unit(el) == "γραμμάρια"
    assert recipe_title(el) == "Ζυμαρικά"
  end

  test "falls back to source names when no translation exists for the locale" do
    user = user_fixture()
    ingredient = ingredient_fixture(%{name: "Kiwi"})
    unit = measurement_unit_fixture(%{name: "grams"})
    _ = ingredient_meal(user, ingredient, unit)

    meals = History.list_calendar_user_meals(user.id, ~D[2026-10-06], ~D[2026-10-06])
    el = History.format_user_meals(meals, "el")

    assert ingredient_title(el) == "Kiwi"
  end

  defp ingredient_title(meals), do: meals |> all_ingredient_meals() |> hd() |> Map.get(:title)
  defp ingredient_unit(meals), do: meals |> all_ingredient_meals() |> hd() |> Map.get(:measurement_unit)

  defp recipe_title(meals) do
    meals
    |> Enum.flat_map(& &1.recipe_user_meals)
    |> hd()
    |> Map.get(:title)
  end

  defp all_ingredient_meals(meals), do: Enum.flat_map(meals, & &1.ingredient_user_meals)
end
