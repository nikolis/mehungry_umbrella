defmodule Mehungry.FoodData.Usda.Parser.Rules.Rule do
  @moduledoc """
  Behaviour for parser rules. Each rule performs exactly one semantic
  transformation on the classified token stream.

  ## Contract

  - `{:ok, result}` — the (possibly unchanged) result continues down the rule
    chain.
  - `{:halt, %Skipped{}}` — the description is not a food; the engine
    short-circuits.

  ## Idempotence

  A rule may only act on tokens with `consumed: false` and must mark every
  token it acts on as consumed (`Rules.Helpers.consume/2`); list appends go
  through `Rules.Helpers.append_unique/2`. Applying any rule twice is
  therefore a no-op.
  """

  alias Mehungry.FoodData.Usda.Parser.{Result, Skipped}

  @callback apply(Result.t()) :: {:ok, Result.t()} | {:halt, Skipped.t()}
end
