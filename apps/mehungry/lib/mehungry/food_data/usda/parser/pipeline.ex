defmodule Mehungry.FoodData.Usda.Parser.Pipeline do
  @moduledoc """
  Entry point of the deterministic USDA description parser:
  Tokenizer → Normalizer → Classifier → RuleEngine.

  Not to be confused with `Mehungry.FoodData.Usda.FoodParser`, which ingests
  FDC JSON payloads into `ingredients` rows — this module parses the
  *description string* of such a row into a canonical semantic structure.

  ## Options

  - `:trace` (default `false`) — accumulate per-stage debug entries on the
    result (`trace` field, JSON-serializable).
  - `:vocabulary` — inject a `%Vocabulary{}` (tests); defaults to the cached
    `Vocabulary.get/0`.

  ## Versioning

  `version/0` is stored on every persisted parse. Bump it whenever rules or
  vocabulary semantics change in a way that should re-parse the corpus.
  """

  alias Mehungry.FoodData.Usda.Parser.{
    Classifier,
    Normalizer,
    Result,
    RuleEngine,
    Skipped,
    Tokenizer,
    Vocabulary
  }

  @parser_version "1.1.0"

  @spec version() :: String.t()
  def version, do: @parser_version

  @spec parse(String.t(), keyword()) :: {:ok, Result.t()} | {:skipped, Skipped.t()}
  def parse(text, opts \\ []) when is_binary(text) do
    vocabulary = Keyword.get_lazy(opts, :vocabulary, &Vocabulary.get/0)
    raw_segments = Tokenizer.tokenize(text)

    segments =
      raw_segments
      |> Enum.map(fn phrases ->
        phrases |> Enum.map(&Normalizer.normalize/1) |> Enum.reject(&(&1 == ""))
      end)
      |> Enum.reject(&(&1 == []))

    %Result{raw_text: text, segments: segments, trace: if(opts[:trace], do: [], else: nil)}
    |> Result.put_trace(%{stage: :tokenizer, output: raw_segments})
    |> Result.put_trace(%{stage: :normalizer, output: segments})
    |> Classifier.classify(vocabulary)
    |> RuleEngine.run()
  end
end
