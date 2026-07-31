defmodule Mehungry.FoodData.Usda.Parser.Rules.PickleRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.PickleRule

  defp pickle_token do
    token(:processing, "pickled",
      raw: "pickle",
      meta: %{head: true, implied_food: "cucumber", implied_food_id: 2}
    )
  end

  test "explicit food token wins over the implied food" do
    result =
      result([pickle_token(), token(:food, "cucumber", segment: 1, meta: %{food_id: 2})])

    assert {:ok, applied} = PickleRule.apply(result)
    assert applied.canonical_food == "cucumber"
    assert applied.canonical_food_id == 2
    assert applied.processing == [:pickled]
    assert applied.confidence == 1.0
  end

  test "bare 'Pickles' falls back to the implied food with a ×0.9 penalty" do
    result = result([pickle_token()])

    assert {:ok, applied} = PickleRule.apply(result)
    assert applied.canonical_food == "cucumber"
    assert applied.canonical_food_id == 2
    assert_in_delta applied.confidence, 0.9, 1.0e-9
  end

  test "is idempotent" do
    {:ok, once} = PickleRule.apply(result([pickle_token()]))
    {:ok, twice} = PickleRule.apply(once)
    assert once == twice
  end

  test "ignores results without a head pickled token" do
    result = result([token(:food, "carrot")])
    assert {:ok, ^result} = PickleRule.apply(result)
  end
end
