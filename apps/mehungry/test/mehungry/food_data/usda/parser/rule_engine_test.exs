defmodule Mehungry.FoodData.Usda.Parser.RuleEngineTest do
  use ExUnit.Case

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.{RuleEngine, Rules, Skipped}

  defmodule SmokedRule do
    use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :smoked
  end

  test "template rules run before FoodHeadRule and tail sweeps run last" do
    rules = RuleEngine.rules()

    assert Enum.find_index(rules, &(&1 == Rules.OilRule)) <
             Enum.find_index(rules, &(&1 == Rules.FoodHeadRule))

    assert Enum.take(rules, 1) == [Rules.NotFoodRule]
    assert Enum.take(rules, -2) == [Rules.ModifierRule, Rules.FinalizeRule]
  end

  test "a not-food token short-circuits the whole chain" do
    result =
      result([token(:not_food, "alcohol"), token(:food, "corn", segment: 1)],
        raw_text: "Alcohol, corn"
      )

    assert {:skipped, %Skipped{reason: :not_food}} = RuleEngine.run(result)
  end

  test "runs the full chain to a finalized result" do
    result =
      result([
        token(:food, "carrot", meta: %{food_id: 1}),
        token(:harvest_stage, "baby", segment: 1),
        token(:processing, "raw", segment: 2)
      ])

    assert {:ok, applied} = RuleEngine.run(result)
    assert applied.canonical_food == "carrot"
    assert applied.harvest_stage == :baby
    assert applied.processing == [:raw]
    assert applied.confidence == 1.0
  end

  test "extra rules from config are spliced before the tail sweeps" do
    Application.put_env(:mehungry, :usda_parser_extra_rules, [SmokedRule])
    on_exit(fn -> Application.delete_env(:mehungry, :usda_parser_extra_rules) end)

    rules = RuleEngine.rules()
    assert SmokedRule in rules

    assert Enum.find_index(rules, &(&1 == SmokedRule)) <
             Enum.find_index(rules, &(&1 == Rules.ModifierRule))

    result = result([token(:food, "salmon"), token(:processing, "smoked", segment: 1)])
    assert {:ok, applied} = RuleEngine.run(result)
    assert applied.processing == [:smoked]
  end
end
