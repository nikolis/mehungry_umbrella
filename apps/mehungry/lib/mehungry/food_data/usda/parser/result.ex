defmodule Mehungry.FoodData.Usda.Parser.Result do
  @moduledoc """
  The accumulator threaded through every parser stage.

  `Mehungry.FoodData.Usda.Parser.Pipeline` seeds it with the raw text, the
  tokenizer/normalizer fill `segments`, the classifier fills `tokens`, and the
  rule engine folds the tokens into the semantic fields (`canonical_food`,
  `harvest_stage`, `processing`, `processing_modifiers`, `packaging`, `part`,
  `dismemberment`, `bone_state`, `portion`, `grade`, `fat`).

  `part` and `dismemberment` are meat-cut descriptors — the USDA primal/body
  part ("loin") and the specific retail cut it was butchered into ("t bone
  steak") — and stay `nil` for anything that isn't sold by the cut.

  `bone_state` ("boneless"), `grade` (USDA quality grade, "choice") and `fat`
  (fat content/trim: "3.25% milkfat", "85% lean 15% fat", "trimmed to 1/8 fat")
  are scalar and `nil` by default; `portion` is a list of tissue/skin
  selections ("meat only", "skinless"), `[]` by default.

  `confidence` starts at 1.0 and is reduced multiplicatively by whichever
  stage detects an anomaly (see `penalize/3`). `trace` is `nil` unless the
  pipeline was invoked with `trace: true`, in which case each stage appends
  JSON-serializable entries for debugging.
  """

  alias Mehungry.FoodData.Usda.Parser.Token

  @type t :: %__MODULE__{
          raw_text: String.t() | nil,
          segments: [[String.t()]],
          tokens: [Token.t()],
          canonical_food: String.t() | nil,
          canonical_food_id: pos_integer() | nil,
          harvest_stage: atom(),
          processing: [atom()],
          processing_modifiers: [String.t()],
          packaging: atom(),
          part: String.t() | nil,
          dismemberment: String.t() | nil,
          bone_state: String.t() | nil,
          portion: [String.t()],
          grade: String.t() | nil,
          fat: String.t() | nil,
          confidence: float(),
          trace: [map()] | nil
        }

  defstruct raw_text: nil,
            segments: [],
            tokens: [],
            canonical_food: nil,
            canonical_food_id: nil,
            harvest_stage: :mature,
            processing: [],
            processing_modifiers: [],
            packaging: :na,
            part: nil,
            dismemberment: nil,
            bone_state: nil,
            portion: [],
            grade: nil,
            fat: nil,
            confidence: 1.0,
            trace: nil

  @doc """
  Multiplies `confidence` by `factor` and records the trace entry (tagged
  with the penalty) when tracing is on.
  """
  @spec penalize(t(), float(), map()) :: t()
  def penalize(%__MODULE__{} = result, factor, trace_entry) do
    %{result | confidence: result.confidence * factor}
    |> put_trace(Map.put(trace_entry, :penalty, factor))
  end

  @doc "Appends a trace entry; no-op when tracing is off (`trace: nil`)."
  @spec put_trace(t(), map()) :: t()
  def put_trace(%__MODULE__{trace: nil} = result, _entry), do: result

  def put_trace(%__MODULE__{trace: trace} = result, entry),
    do: %{result | trace: trace ++ [entry]}
end
