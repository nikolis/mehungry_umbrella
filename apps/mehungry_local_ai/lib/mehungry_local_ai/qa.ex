defmodule MehungryLocalAi.QA do
  @moduledoc """
  Local extractive question-answering serving used by the measurement extractor —
  "How much <compound> does it contain?" against a paper's text yields the answer
  span + a confidence score. A supervised `Nx.Serving` (Bumblebee + EXLA/CPU),
  registered under this module's name.

  Unlike the old in-app serving, this one is **always started** — loading the model
  is the whole point of the local service. It compiles with `compiler: EXLA` without
  touching the global Nx default backend.
  """

  require Logger

  @model "distilbert-base-cased-distilled-squad"
  @batch_size 1
  @sequence_length 384

  # Sliding character window so long full text fits the model, with a small overlap
  # so a value split across a boundary is still captured in a neighbouring window.
  @chunk_chars 1400
  @chunk_overlap 200
  @max_chunks 10

  @doc "HuggingFace repo id of the loaded QA model."
  def model, do: @model

  @doc "Whether the serving should be started (off in tests to skip the model download)."
  def enabled?, do: Application.get_env(:mehungry_local_ai, :start_qa, true)

  @doc "Whether the serving is actually loaded and callable right now."
  def available?, do: enabled?() and is_pid(Process.whereis(__MODULE__))

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  def start_link(_opts) do
    if enabled?() do
      Logger.info("MehungryLocalAi.QA: starting Nx.Serving for #{@model} (EXLA/CPU)")

      Nx.Serving.start_link(
        serving: build_serving(),
        name: __MODULE__,
        batch_size: @batch_size,
        batch_timeout: 100
      )
    else
      Logger.info("MehungryLocalAi.QA: disabled (:start_qa=false) — rule-based extraction only")
      :ignore
    end
  end

  @doc """
  Builds the (unstarted) Bumblebee QA serving. Blocking/slow on first call — downloads
  the model and compiles the EXLA kernels. Uses `compiler: EXLA` locally without
  touching the global Nx default backend.
  """
  def build_serving do
    {:ok, model_info} = Bumblebee.load_model({:hf, @model})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @model})

    Bumblebee.Text.question_answering(model_info, tokenizer,
      compile: [batch_size: @batch_size, sequence_length: @sequence_length],
      defn_options: [compiler: EXLA]
    )
  end

  @doc """
  Ask `question` against `context`, chunking long text and returning the best-scoring
  answer as `%{text, score}`, or `nil` when the serving is unavailable / no answer.
  """
  @spec answer(String.t(), String.t()) :: %{text: String.t(), score: float()} | nil
  def answer(question, context) when is_binary(question) and is_binary(context) do
    if available?() do
      context
      |> chunks()
      |> Enum.map(&run_one(question, &1))
      |> Enum.reject(&is_nil/1)
      |> case do
        [] -> nil
        results -> Enum.max_by(results, & &1.score)
      end
    else
      nil
    end
  end

  defp run_one(question, context) do
    case Nx.Serving.batched_run(__MODULE__, %{question: question, context: context}) do
      %{results: [%{text: text, score: score} | _]} when is_binary(text) and text != "" ->
        %{text: text, score: score}

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp chunks(text) do
    if String.length(text) <= @chunk_chars do
      [text]
    else
      step = @chunk_chars - @chunk_overlap

      0..div(String.length(text), step)
      |> Enum.map(&String.slice(text, &1 * step, @chunk_chars))
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.take(@max_chunks)
    end
  end
end
