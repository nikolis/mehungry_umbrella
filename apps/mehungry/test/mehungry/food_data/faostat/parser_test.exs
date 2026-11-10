defmodule Mehungry.FoodData.Faostat.ParserTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Faostat.Parser

  @rows [
    %{item_code: "515", item: "Apples", area: "China", year: 2021, value_tonnes: 40_000_000.0},
    %{item_code: "515", item: "Apples", area: "China", year: 2022, value_tonnes: 47_571_100.0},
    %{item_code: "515", item: "Apples", area: "Turkey", year: 2022, value_tonnes: 4_817_500.0},
    %{item_code: "515", item: "Apples", area: "USA", year: 2022, value_tonnes: 4_429_330.0},
    %{item_code: "515", item: "Apples", area: "Poland", year: 2022, value_tonnes: 4_264_700.0},
    %{item_code: "388", item: "Tomatoes", area: "India", year: 2022, value_tonnes: 20_000_000.0}
  ]

  describe "top_producers/3" do
    test "returns the latest year's top-N by tonnage, ranked descending" do
      assert [
               %{country: "China", year: 2022},
               %{country: "Turkey", year: 2022},
               %{country: "USA", year: 2022}
             ] = Parser.top_producers(@rows, "515", 3)
    end

    test "ignores older years (only the latest present is used)" do
      producers = Parser.top_producers(@rows, "515", 5)
      assert Enum.all?(producers, &(&1.year == 2022))
      refute Enum.any?(producers, &(&1.tonnes == 40_000_000.0))
    end

    test "returns [] for an unknown item code" do
      assert [] == Parser.top_producers(@rows, "999", 3)
    end
  end

  describe "items/1" do
    test "returns distinct {code, item} pairs sorted by name" do
      assert [{"515", "Apples"}, {"388", "Tomatoes"}] = Parser.items(@rows)
    end
  end
end
