defmodule Mehungry.FoodData.Usda.Parser.RuleEngine do
  @moduledoc """
  Folds the ordered rule chain over a classified
  `Mehungry.FoodData.Usda.Parser.Result`.

  Order is load-bearing: template rules (oil/pickle/juice) must consume their
  tokens before `FoodHeadRule` resolves the food, and the `ModifierRule` /
  `FinalizeRule` sweeps always run last. Extra rules can be spliced in
  without touching this module:

      config :mehungry, :usda_parser_extra_rules,
        [Mehungry.FoodData.Usda.Parser.Rules.SmokedRule]
  """

  alias Mehungry.FoodData.Usda.Parser.{Result, Rules, Skipped}

  @default_rules [
    Rules.NotFoodRule,
    Rules.PreparedDishRule,
    Rules.OilRule,
    Rules.PickleRule,
    Rules.JuiceRule,
    Rules.FoodHeadRule,
    Rules.BabyRule,
    Rules.PartRule,
    Rules.DismembermentRule,
    Rules.BoneStateRule,
    Rules.PortionRule,
    Rules.GradeRule,
    Rules.FatRule,
    Rules.RawRule,
    Rules.RoastedRule,
    Rules.BoiledRule,
    Rules.FrozenRule,
    Rules.DriedRule,
    Rules.PureeRule,
    Rules.SeedRule,
    Rules.LeafRule,
    Rules.FruitRule,
    Rules.CannedRule
  ]

  @tail_rules [Rules.ModifierRule, Rules.FinalizeRule]

  @spec rules() :: [module()]
  def rules do
    @default_rules ++ Application.get_env(:mehungry, :usda_parser_extra_rules, []) ++ @tail_rules
  end

  @spec run(Result.t()) :: {:ok, Result.t()} | {:skipped, Skipped.t()}
  def run(%Result{} = result) do
    Enum.reduce_while(rules(), {:ok, result}, fn rule, {:ok, acc} ->
      case rule.apply(acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:halt, %Skipped{} = skipped} -> {:halt, {:skipped, skipped}}
      end
    end)
  end
end
