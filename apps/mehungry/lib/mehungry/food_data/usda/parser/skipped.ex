defmodule Mehungry.FoodData.Usda.Parser.Skipped do
  @moduledoc """
  Terminal parse outcome for descriptions that are not a food the pipeline
  should canonicalize (e.g. "Alcoholic beverage, daiquiri, canned").

  Emitted when a rule halts the engine, currently only
  `Mehungry.FoodData.Usda.Parser.Rules.NotFoodRule`.
  """

  @type t :: %__MODULE__{
          reason: atom(),
          text: String.t(),
          confidence: float(),
          trace: [map()] | nil
        }

  @enforce_keys [:reason, :text]
  defstruct [:reason, :text, confidence: 1.0, trace: nil]
end
