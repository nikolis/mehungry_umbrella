defmodule Mehungry.ObanWorkers.CanonicalFoodEmbeddingWorker do
  @moduledoc """
  Computes and stores the semantic embedding of a canonical-food name, so
  `Mehungry.AI.SemanticMatcher.search/2` has vectors to cosine-search against.
  Without this backfill the `canonical_foods.embedding` column stays NULL and
  semantic matching returns nothing.

  Mirrors `RecipeEmbeddingWorker`: one job per row, plus `enqueue_all/0` to
  backfill every lexicon entry missing an embedding. Runs on the `:imports`
  queue and routes through the shared serving via `SemanticMatcher.embed/1`, so
  it is a no-op (returns `{:error, ...}` → Oban retry) unless `:enable_embeddings`
  is on — i.e. it only does real work on the embedding-enabled task.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.CanonicalFood
  alias Mehungry.AI.SemanticMatcher

  # Kept in sync with Mehungry.AI.EmbeddingServer's model; stamped on each row so
  # a model change is detectable and re-embeddable.
  @embedding_model "BAAI/bge-small-en-v1.5"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"canonical_food_id" => id}}) do
    case Repo.get(CanonicalFood, id) do
      nil ->
        # Row deleted between enqueue and run — nothing to do.
        :ok

      %CanonicalFood{name: name} ->
        case SemanticMatcher.embed(name) do
          {:ok, vector} ->
            store_embedding(id, vector)
            Logger.info("CanonicalFoodEmbeddingWorker: embedded canonical_food #{id}")
            :ok

          {:error, reason} ->
            Logger.warning(
              "CanonicalFoodEmbeddingWorker: embed failed for #{id}: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  @doc "Enqueue embedding generation for one canonical food."
  def enqueue(canonical_food_id) do
    %{canonical_food_id: canonical_food_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  @doc "Enqueue embedding generation for every canonical food missing an embedding."
  def enqueue_all do
    ids =
      Repo.all(from(f in CanonicalFood, where: is_nil(f.embedding), select: f.id))

    Enum.each(ids, &enqueue/1)
    Logger.info("CanonicalFoodEmbeddingWorker: enqueued #{length(ids)} canonical foods")
    length(ids)
  end

  # Stored via raw SQL (parameterized) so this worker needs no schema field and
  # matches SemanticMatcher's own vector-literal convention. `<=>` cosine search
  # is normalization-invariant, so the stored vector need not be pre-normalized.
  defp store_embedding(id, vector) do
    literal = "[" <> Enum.map_join(vector, ",", &to_string/1) <> "]"

    Repo.query!(
      "UPDATE canonical_foods SET embedding = $1::vector, embedding_model = $2, updated_at = NOW() WHERE id = $3",
      [literal, @embedding_model, id]
    )
  end
end
