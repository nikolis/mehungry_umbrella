defmodule Mehungry.UtilsTest do
  use Mehungry.DataCase

  alias Mehungry.Utils

  describe "test measurement unit normalization" do
    test "get_bigger_mu" do
      result = Utils.get_bigger_mu("gram")
      assert result == "kg"
    end

    test "get_smaller_mu" do
      result = Utils.get_smaller_mu("l")
      assert result == "ml"
    end

    test "normilize up" do
      result = Utils.normilize_measurement_unit("gram", 3500)
      assert result == {3.5, "kg"}
    end

    test "normilize down" do
      result = Utils.normilize_measurement_unit("l", 0.4)
      assert result == {400, "ml"}
    end
  end

  describe "test sort_ingredients for basket" do
    test "sort ingredients for baskjet" do
      result =
        Utils.sort_ingredients_for_basket([
          %{in_storage: true},
          %{in_storage: false},
          %{in_storage: true},
          %{in_storage: false},
          %{in_storage: true}
        ])
    end
  end
end
