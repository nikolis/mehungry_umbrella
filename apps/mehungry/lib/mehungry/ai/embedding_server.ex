# apps/mehungry/lib/mehungry/ai/embedding_server.ex
defmodule Mehungry.AI.EmbeddingServer do
  @moduledoc """
  The shared Bumblebee embedding model, held in a supervised `Nx.Serving`
  registered under this module's name.

  Started **only when `:enable_embeddings` is true** — otherwise `start_link/1`
  returns `:ignore` and no model is loaded (keeps the constrained web/worker
  task and the test suite from downloading/compiling the model). Callers embed
  through `Nx.Serving.batched_run(#{inspect(__MODULE__)}, input)`, which is what
  `Mehungry.AI.SemanticMatcher` does — automatic cross-request batching, no
  hand-rolled GenServer message passing.
  """

  require Logger

  @model "sentence-transformers/all-MiniLM-L6-v2"
  @batch_size 16
  @sequence_length 64

  @doc "HuggingFace repo id of the loaded model."
  def model, do: @model

  @doc "Whether the serving should run in this node/task."
  def enabled?, do: Application.get_env(:mehungry, :enable_embeddings, false)

  def child_spec(opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}
  end

  @doc """
  Starts the named `Nx.Serving`, or `:ignore` when embeddings are disabled (a
  supervisor treats `:ignore` as success and starts no child).
  """
  def start_link(_opts) do
    if enabled?() do
      Logger.info("EmbeddingServer: starting Nx.Serving for #{@model} (EXLA/CPU)")

      Nx.Serving.start_link(
        serving: build_serving(),
        name: __MODULE__,
        batch_size: @batch_size,
        batch_timeout: 100
      )
    else
      Logger.info("EmbeddingServer: embeddings disabled by config (:enable_embeddings)")
      :ignore
    end
  end

  @doc """
  Builds the (unstarted) Bumblebee text-embedding serving. Blocking/slow on
  first call — downloads the model and compiles the EXLA kernels.
  """
  def build_serving do
    Nx.default_backend(EXLA.Backend)

    {:ok, model_info} = Bumblebee.load_model({:hf, @model}, architecture: :base)
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, @model})

    Bumblebee.Text.text_embedding(model_info, tokenizer,
      # Fixed compile shapes so EXLA compiles once, not per batch.
      compile: [batch_size: @batch_size, sequence_length: @sequence_length],
      defn_options: [compiler: EXLA],
      output_attribute: :hidden_state,
      output_pool: :cls_token_pooling,
      # L2-normalize so pgvector cosine distance is directly comparable.
      embedding_processor: :l2_norm
    )
  end
end
