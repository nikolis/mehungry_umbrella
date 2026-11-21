defmodule Mehungry.Food.SpeciesNutritionSummaryTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.SpeciesNutritionSummary, as: Summary

  defp node(name, amount, unit, children \\ []) do
    %{"name" => name, "amount" => amount, "measurement_unit" => unit, "children" => children}
  end

  defp tree do
    %{
      "Carbohydrates" =>
        node("Carbohydrates", 8.1, "gram", [
          node("Total Sugars", 3.2, "gram", [
            node("Glucose", 1.5, "gram"),
            node("Fructose", 1.4, "gram")
          ])
        ]),
      "Total Fat" =>
        node("Total Fat", 2.0, "gram", [
          node("Saturated Fat", 0.3, "gram"),
          node("Monounsaturated Fat", 1.0, "gram")
        ]),
      "Minerals" =>
        node("Minerals", 0, "milligram", [
          node("Potassium, K", 123.0, "milligram"),
          node("Iron, Fe", 0.25, "milligram"),
          node("Sodium, Na", 0.0, "milligram")
        ]),
      "Vitamins" => node("Vitamins", 0, "milligram", [node("Vitamin C", 1.3, "milligram")])
    }
  end

  test "composition_summary/2 names the sugars and the fat quality" do
    assert Summary.composition_summary("Eggplant, raw", tree()) ==
             "Per 100 g, Eggplant, raw contains 3.2 g of total sugars, led by glucose and fructose. " <>
               "Its fat is mostly unsaturated."
  end

  test "composition_summary/2 is nil for an empty tree" do
    assert Summary.composition_summary("Eggplant", %{}) == nil
  end

  test "micronutrient_summary/2 lists positive micros in priority order" do
    assert Summary.micronutrient_summary("Eggplant", tree()) ==
             "Per 100 g, Eggplant also provides 0.250 mg iron, 123.0 mg potassium and 1.3 mg vitamin C."
  end

  test "micronutrient_summary/2 is nil without mineral/vitamin groups" do
    assert Summary.micronutrient_summary("Eggplant", %{}) == nil
  end

  test "default_ingredient/1 prefers a Foundation-class food, else the first" do
    a = %{id: 1, food_class: "Survey"}
    b = %{id: 2, food_class: "Foundation"}

    assert Summary.default_ingredient([a, b]) == b
    assert Summary.default_ingredient([a]) == a
    assert Summary.default_ingredient([]) == nil
  end
end
