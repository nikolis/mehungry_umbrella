defmodule Mehungry.FoodData.Usda.Parser.Token do
  @moduledoc """
  A classified phrase from a USDA food description.

  Produced by `Mehungry.FoodData.Usda.Parser.Classifier`, consumed by the
  rules in `Mehungry.FoodData.Usda.Parser.Rules`. A rule that acts on a token
  marks it `consumed: true`; subsequent rules ignore consumed tokens, which is
  what makes every rule idempotent.
  """

  @type type ::
          :food
          | :processing
          | :harvest_stage
          | :part
          | :dismemberment
          | :bone_state
          | :portion
          | :grade
          | :prepared
          | :modifier
          | :packaging
          | :not_food
          | :unknown

  @type t :: %__MODULE__{
          type: type(),
          raw: String.t(),
          value: String.t(),
          segment: non_neg_integer(),
          position: non_neg_integer(),
          meta: map(),
          consumed: boolean()
        }

  @enforce_keys [:type, :raw, :value, :segment]
  defstruct [:type, :raw, :value, :segment, position: 0, meta: %{}, consumed: false]
end
