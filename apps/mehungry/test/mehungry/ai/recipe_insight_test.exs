defmodule Mehungry.AI.RecipeInsightTest do
  use ExUnit.Case, async: true

  alias Mehungry.AI.{InsightCaptioner, RecipeInsight}
  alias Mehungry.Food.Recipe

  # A recipe struct carrying only the fields the pure insight functions read —
  # the cached `nutrients` jsonb map (whole-recipe totals) + `servings`.
  defp recipe(nutrients, servings) do
    %Recipe{id: 1, title: "Test Bowl", description: "tasty", nutrients: nutrients, servings: servings}
  end

  describe "macros/1" do
    test "reads the macro keys and divides whole-recipe totals by servings" do
      nutrients = %{
        "Energy" => %{"amount" => 800.0},
        "Protein" => %{"amount" => 40.0},
        "Total Fat" => %{"amount" => 24.0},
        "Carbohydrates" => %{
          "amount" => 60.0,
          "children" => [%{"name" => "Fiber, total dietary", "amount" => 12.0}]
        }
      }

      m = RecipeInsight.macros(recipe(nutrients, 2))

      assert m.calories == 400.0
      assert m.protein_g == 20.0
      assert m.fat_g == 12.0
      assert m.carbs_g == 30.0
      assert m.fiber_g == 6.0
    end

    test "treats missing nutrition as zeros and nil servings as one" do
      m = RecipeInsight.macros(recipe(%{}, nil))

      assert m.calories == 0.0
      assert m.protein_g == 0.0
      assert m.fiber_g == nil
    end
  end

  describe "fallback/2" do
    test "turns the top candidate into a deterministic headline/caption" do
      candidates = [
        %{type: "compound", headline_hint: "Rich in Polyphenols", detail: %{}},
        %{type: "balanced", headline_hint: "Balanced Macros", detail: %{}}
      ]

      result = InsightCaptioner.fallback(recipe(%{}, 1), candidates)

      assert result.insight_type == "compound"
      assert result.headline == "Rich in Polyphenols"
      assert result.caption =~ "Test Bowl"
      assert result.caption =~ "Rich in Polyphenols"
    end
  end
end
