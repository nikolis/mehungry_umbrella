defmodule MehungryWeb.WeeklyPlanGraphicTest do
  @moduledoc """
  Guards the shareable weekly-plan card: the deterministic `build_week_data/3`
  (grid layout + daily-average macros from the exact meals, no re-derivation) and
  a render smoke test (the prod vips/rsvg/font risk gate — same gate as the recipe
  insight graphic).
  """
  use ExUnit.Case, async: true

  alias MehungryWeb.{WeeklyPlanGraphic, WeeklyPlanGraphicGenerator}

  @week_start ~D[2026-10-06]

  # A recipe meal in the `History.format_user_meals/1` shape, with 1 serving fully
  # consumed so `summarize_meals_nutrients/1` counts the whole recipe.
  defp recipe_meal(date, meal_type, title, nutrients) do
    %{
      id: System.unique_integer([:positive]),
      start_dt: NaiveDateTime.new!(date, ~T[12:00:00]),
      meal_type: meal_type,
      recipe_user_meals: [
        %{title: title, recipe_nutrients: nutrients, consume_portions: 1, servings: 1}
      ],
      ingredient_user_meals: [],
      free_food_user_meals: []
    }
  end

  defp nutrients(kcal, protein) do
    %{
      "Energy" => %{"amount" => kcal * 1.0, "measurement_unit" => "kcal"},
      "Protein" => %{"amount" => protein * 1.0, "measurement_unit" => "g"}
    }
  end

  describe "build_week_data/3" do
    test "empty week is rejected" do
      assert {:error, :empty_week} = WeeklyPlanGraphicGenerator.build_week_data(@week_start, [])
    end

    test "builds a 7-day grid with meals on the right days, ordered by meal type" do
      day0 = @week_start
      day2 = Date.add(@week_start, 2)

      meals = [
        # Added dinner-first to prove the grid re-orders by meal type.
        recipe_meal(day0, "dinner", "Salmon", nutrients(600, 40)),
        recipe_meal(day0, "breakfast", "Omelette", nutrients(400, 20)),
        recipe_meal(day2, "lunch", "Lentil soup", nutrients(500, 25))
      ]

      assert {:ok, %{week_data: wd}} =
               WeeklyPlanGraphicGenerator.build_week_data(@week_start, meals)

      assert length(wd.days) == 7
      [d0, d1, d2 | _] = wd.days

      assert d0.label == Calendar.strftime(day0, "%a")
      # Ordered by meal type (breakfast before dinner) and tagged with the label.
      assert d0.meals == [
               %{tag: "Breakfast", title: "Omelette"},
               %{tag: "Dinner", title: "Salmon"}
             ]

      assert d1.meals == []
      assert d2.meals == [%{tag: "Lunch", title: "Lentil soup"}]
    end

    test "a full 5-slot day keeps all five meal lines (no collapse)" do
      day0 = @week_start

      meals =
        for mt <- ~w(breakfast morning_snack lunch afternoon_snack dinner) do
          recipe_meal(day0, mt, "meal-#{mt}", nutrients(300, 15))
        end

      assert {:ok, %{week_data: wd}} =
               WeeklyPlanGraphicGenerator.build_week_data(@week_start, meals)

      [d0 | _] = wd.days
      tags = Enum.map(d0.meals, & &1.tag)

      assert tags == ["Breakfast", "Morning Snack", "Lunch", "Afternoon Snack", "Dinner"]
      refute Enum.any?(d0.meals, &(&1.title =~ "more"))
    end

    test "multiple items in one slot are joined into a single line" do
      day0 = @week_start

      meal = %{
        id: 1,
        start_dt: NaiveDateTime.new!(day0, ~T[08:00:00]),
        meal_type: "breakfast",
        recipe_user_meals: [%{title: "Eggs", recipe_nutrients: nutrients(200, 12), consume_portions: 1, servings: 1}],
        ingredient_user_meals: [%{title: "Toast"}],
        free_food_user_meals: []
      }

      assert {:ok, %{week_data: wd}} =
               WeeklyPlanGraphicGenerator.build_week_data(@week_start, [meal])

      [d0 | _] = wd.days
      assert d0.meals == [%{tag: "Breakfast", title: "Eggs, Toast"}]
    end

    test "macros are the week total divided by 7 (daily average)" do
      # One 700 kcal / 70 g protein meal in the whole week → avg = 100 / 10.
      meals = [recipe_meal(~D[2026-10-07], "lunch", "Big bowl", nutrients(700, 70))]

      assert {:ok, %{week_data: wd, summary: summary}} =
               WeeklyPlanGraphicGenerator.build_week_data(@week_start, meals)

      assert summary.energy_kcal == 100
      assert summary.protein_g == 10.0
      assert wd.macros.calories == 100
      assert wd.macros.protein_g == 10.0
    end

    test "goal label flows into the caption" do
      meals = [recipe_meal(~D[2026-10-07], "lunch", "Bowl", nutrients(700, 70))]

      assert {:ok, %{caption: caption}} =
               WeeklyPlanGraphicGenerator.build_week_data(@week_start, meals,
                 goal_label: "Anti-inflammatory"
               )

      assert caption =~ "Anti-inflammatory week"
      assert caption =~ "100 kcal/day"
    end
  end

  describe "render/1" do
    test "renders a non-empty PNG (vips/rsvg/font render gate)" do
      week_data = %{
        range_label: "6 Oct – 12 Oct",
        goal_label: "Anti-inflammatory",
        days: [
          %{label: "Mon", meals: ["Omelette", "Soup", "Salmon"]},
          %{label: "Tue", meals: []},
          %{label: "Wed", meals: ["Oats"]},
          %{label: "Thu", meals: []},
          %{label: "Fri", meals: []},
          %{label: "Sat", meals: []},
          %{label: "Sun", meals: []}
        ],
        macros: %{protein_g: 112.0, carbs_g: 180.0, fat_g: 60.0, calories: 1900},
        share_url: "m3hungry.com"
      }

      assert {:ok, binary} = WeeklyPlanGraphic.render(week_data)
      assert is_binary(binary)
      assert byte_size(binary) > 1000
      # PNG magic bytes.
      assert <<0x89, "PNG", "\r\n", 0x1A, "\n", _rest::binary>> = binary
    end
  end
end
