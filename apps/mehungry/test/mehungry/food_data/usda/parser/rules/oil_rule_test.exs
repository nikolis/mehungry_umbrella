defmodule Mehungry.FoodData.Usda.Parser.Rules.OilRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.OilRule

  test "'Oil, corn' → food corn, processing [:oil]" do
    result =
      result([
        token(:processing, "oil", meta: %{head: true}),
        token(:food, "corn", segment: 1, meta: %{food_id: 3})
      ])

    assert {:ok, applied} = OilRule.apply(result)
    assert applied.canonical_food == "corn"
    assert applied.canonical_food_id == 3
    assert applied.processing == [:oil]
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "head oil without a following food still records the processing" do
    result = result([token(:processing, "oil", meta: %{head: true})])

    assert {:ok, applied} = OilRule.apply(result)
    assert applied.processing == [:oil]
    assert applied.canonical_food == nil
  end

  test "non-head oil token (e.g. 'Corn oil spread' qualifier) is left alone" do
    result = result([token(:processing, "oil", segment: 1)])
    assert {:ok, ^result} = OilRule.apply(result)
  end

  test "is idempotent" do
    result =
      result([
        token(:processing, "oil", meta: %{head: true}),
        token(:food, "corn", segment: 1, meta: %{food_id: 3})
      ])

    {:ok, once} = OilRule.apply(result)
    {:ok, twice} = OilRule.apply(once)
    assert once == twice
  end
end
