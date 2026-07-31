# apps/mehungry/lib/mehungry/ai/semantic_matcher.ex
defmodule Mehungry.AI.SemanticMatcher do
  @moduledoc """
  Semantic matching using Bumblebee/Nx for fuzzy food name matching.
  Only used when deterministic parser fails.
  """

  require Logger

  alias Mehungry.AI.EmbeddingServer
  alias Mehungry.Repo

  @similarity_threshold 0.75

  @doc "Default cosine-similarity cutoff for a match to count."
  def similarity_threshold, do: @similarity_threshold

  @doc "HuggingFace repo id of the model behind the serving (for provenance)."
  def model_name, do: EmbeddingServer.model()

  @doc """
  Find semantically similar canonical foods for a query.
  """
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold, @similarity_threshold)

    with {:ok, embedding} <- embed(query),
         {:ok, results} <- vector_search(embedding, limit, threshold) do
      {:ok, results}
    else
      {:error, reason} ->
        Logger.warning("Semantic search failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generate embedding for a single text.
  """
  @spec embed(String.t()) :: {:ok, [float()]} | {:error, term()}
  def embed(text) when is_binary(text) do
    with :ok <- ensure_available() do
      # text_embedding serving yields %{embedding: tensor} per input.
      %{embedding: tensor} = Nx.Serving.batched_run(EmbeddingServer, text)
      {:ok, Nx.to_flat_list(tensor)}
    end
  rescue
    e ->
      Logger.error("Embedding error: #{inspect(e)}")
      {:error, e}
  end

  @doc """
  Batch embed multiple texts. Returns embeddings in input order.
  """
  @spec embed_all([String.t()]) :: {:ok, [[float()]]} | {:error, term()}
  def embed_all([]), do: {:ok, []}

  def embed_all(texts) when is_list(texts) do
    with :ok <- ensure_available() do
      results = Nx.Serving.batched_run(EmbeddingServer, texts)
      {:ok, Enum.map(results, fn %{embedding: tensor} -> Nx.to_flat_list(tensor) end)}
    end
  rescue
    e ->
      Logger.error("Batch embedding error: #{inspect(e)}")
      {:error, e}
  end

  # The serving is registered under the EmbeddingServer name only when
  # :enable_embeddings is on and the model finished loading.
  defp ensure_available do
    cond do
      not Application.get_env(:mehungry, :enable_embeddings, false) ->
        {:error, :embeddings_disabled}

      is_nil(Process.whereis(EmbeddingServer)) ->
        {:error, :serving_not_started}

      true ->
        :ok
    end
  end

  defp vector_search(embedding, limit, threshold) do
    # Check if pgvector extension is available
    case check_pgvector() do
      :ok ->
        do_vector_search(embedding, limit, threshold)

      {:error, reason} ->
        Logger.warning("pgvector not available: #{reason}")
        {:error, reason}
    end
  end

  defp do_vector_search(embedding, limit, threshold) do
    query = """
    SELECT 
      cf.id,
      cf.name,
      1 - (cf.embedding <=> $1::vector) as similarity
    FROM canonical_foods cf
    WHERE cf.embedding IS NOT NULL
      AND 1 - (cf.embedding <=> $1::vector) >= $2
    ORDER BY similarity DESC
    LIMIT $3
    """

    params = [
      to_vector(embedding),
      threshold,
      limit
    ]

    case Repo.query(query, params) do
      {:ok, %{rows: rows}} ->
        results =
          Enum.map(rows, fn [id, name, similarity] ->
            %{
              id: id,
              name: name,
              similarity: similarity
            }
          end)

        {:ok, results}

      error ->
        error
    end
  end

  defp check_pgvector do
    case Repo.query("SELECT extversion FROM pg_extension WHERE extname = 'vector'", []) do
      {:ok, %{rows: []}} -> {:error, :extension_not_installed}
      {:ok, _} -> :ok
      error -> {:error, error}
    end
  end

  defp to_vector(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &Float.to_string/1) <> "]"
  end

  @doc """
  Check if semantic matching is available.
  """
  @spec available?() :: boolean()
  def available? do
    Application.get_env(:mehungry, :enable_embeddings, false) and
      Process.whereis(Mehungry.AI.EmbeddingServer) != nil and
      check_pgvector() == :ok
  end
end
