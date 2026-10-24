defmodule Mehungry.FoodData.MyPlate.IngredientParserTest do
  @moduledoc """
  Pure, DB-free coverage of the MyPlate free-text ingredient-line parser —
  quantity (integer / decimal / simple + mixed + unicode fractions / ranges),
  unit detection vs. count items, name extraction, and note handling.
  """
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.MyPlate.IngredientParser, as: P

  describe "quantity parsing" do
    test "integer" do
      assert %{quantity: 1.0, unit: "cup", name: "sugar"} = P.parse("1 cup sugar")
    end

    test "decimal" do
      assert %{quantity: 0.5, unit: "pound", name: "ground beef"} = P.parse("0.5 pound ground beef")
    end

    test "simple fraction" do
      assert %{quantity: 0.25, unit: "cup", name: "vegetable oil"} = P.parse("1/4 cup vegetable oil")
    end

    test "mixed fraction" do
      # Plural unit is kept verbatim ("cups"); the resolver's aliases map it.
      assert %{quantity: 1.5, unit: "cups", name: "whole wheat flour"} =
               P.parse("1 1/2 cups whole wheat flour")
    end

    test "unicode fraction alone" do
      assert %{quantity: 0.5, unit: "cup", name: "raisins"} = P.parse("½ cup raisins")
    end

    test "unicode fraction attached to a whole number is a mixed fraction" do
      assert %{quantity: 1.5, unit: "cups", name: "milk"} = P.parse("1½ cups milk")
    end

    test "numeric range takes the lower bound and drops the upper from the name" do
      assert %{quantity: 2.0, unit: "tablespoons", name: "olive oil"} =
               P.parse("2 to 3 tablespoons olive oil")

      assert %{quantity: 2.0, name: "olive oil"} = P.parse("2-3 tablespoons olive oil")
    end

    test "no leading number defaults to 1.0" do
      assert %{quantity: 1.0, unit: "piece", name: "Salt to taste"} = P.parse("Salt to taste")
    end
  end

  describe "unit vs count item" do
    test "a recognized unit is consumed" do
      assert %{unit: "teaspoon", name: "vanilla"} = P.parse("1/2 teaspoon vanilla")
    end

    test "abbreviations are canonicalized to a resolver-friendly form" do
      assert %{unit: "tablespoon"} = P.parse("2 tbsp butter")
      assert %{unit: "teaspoon"} = P.parse("1 tsp salt")
      assert %{unit: "ounce"} = P.parse("8 oz cream cheese")
      assert %{unit: "pound"} = P.parse("1 lb carrots")
    end

    test "a non-unit token after the quantity is a count item (unit: piece)" do
      assert %{quantity: 3.0, unit: "piece", name: "eggs"} = P.parse("3 eggs")
    end

    test "plural count noun stays in the name" do
      assert %{quantity: 2.0, unit: "cloves", name: "garlic"} = P.parse("2 cloves garlic")
    end
  end

  describe "name extraction" do
    test "strips a leading 'of'" do
      assert %{name: "flour"} = P.parse("1 cup of flour")
    end

    test "name is trimmed" do
      assert %{name: "sugar"} = P.parse("1 cup  sugar  ")
    end
  end

  describe "original (display) text" do
    test "no note → verbatim text" do
      assert %{original: "1 cup sugar"} = P.parse("1 cup sugar")
    end

    test "note is appended in parens, not folded into the search name" do
      parsed = P.parse("1/4 cup vegetable oil", "or cooking oil of your choice")
      assert parsed.name == "vegetable oil"
      assert parsed.original == "1/4 cup vegetable oil (or cooking oil of your choice)"
    end

    test "blank note is ignored" do
      assert %{original: "2 cups zucchini"} = P.parse("2 cups zucchini", "")
    end
  end
end
