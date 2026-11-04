defmodule MehungryWeb.CalendarLive.Calendar.MealCoreTest do
  @moduledoc false

  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MehungryWeb.CalendarLive.Calendar.MealCore

  # The macro-summary shape `summary_tags/1` consumes (see
  # `NutrientUtils.macro_summary/1`), with sodium/sat-fat present.
  defp metrics(overrides \\ %{}) do
    Enum.into(overrides, %{
      meal_count: 2,
      total_items: 3,
      energy_kcal: 1800,
      calorie_target: nil,
      protein_g: 90,
      fat_g: 60,
      carbs_g: 200,
      sugars_g: 40,
      fiber_g: 25,
      sodium_mg: 1500,
      saturated_fat_g: 12.0
    })
  end

  describe "summary_tags/1" do
    test "renders sodium and saturated-fat badges when present" do
      html = render_component(&MealCore.summary_tags/1, metrics())

      assert html =~ "sodium"
      assert html =~ "1500"
      assert html =~ "sat. fat"
      assert html =~ "12.0"
    end

    test "hides sodium and saturated-fat badges when zero (not recorded)" do
      html = render_component(&MealCore.summary_tags/1, metrics(%{sodium_mg: 0, saturated_fat_g: +0.0}))

      refute html =~ "sodium"
      refute html =~ "sat. fat"
      # The always-on macro badges still render.
      assert html =~ "protein"
      assert html =~ "carbs"
    end
  end

  describe "card_meal/1 ingredient icon" do
    # Minimal assigns for an ingredient card. `actual_meal.id == "landing_id"`
    # skips the edit/copy buttons (so no `myself`/event wiring needed).
    defp card_assigns(overrides) do
      Enum.into(overrides, %{
        card_meal_text: "text-parchment",
        img_url: nil,
        actual_meal: %{id: "landing_id"},
        title: "Spinach",
        cooking_portions: 1,
        consume_portions: nil
      })
    end

    test "renders the emoji before the title when icon is set" do
      html = render_component(&MealCore.card_meal/1, card_assigns(%{icon: "🥬"}))

      assert html =~ "🥬"
      assert html =~ "Spinach"
    end

    test "omits the emoji when no icon is passed (recipe/landing cards)" do
      html = render_component(&MealCore.card_meal/1, card_assigns(%{title: "Pasta night"}))

      refute html =~ "🥬"
      assert html =~ "Pasta night"
    end
  end
end
