defmodule Mehungry.ObanWorkers.ParserSuggestionWorker do
  @moduledoc """
  Generates semantic suggestions for the deterministic parser's low-confidence,
  unresolved parses, one id-ordered batch per tick.

  Mirrors `IngredientFoodParsingWorker`'s self-re-enqueue chain, threading a
  `cursor` (last processed `ingredient_parsed_foods.id`) until no unresolved
  parses remain. Cursor-based termination holds even when a parse yields no match
  above threshold; `ParserSuggestions.generate_batch/2` is idempotent, so Oban
  retries are safe. Runs on `:imports` and only does real work when
  `:enable_embeddings` is on and `canonical_foods.embedding` is populated (run
  `CanonicalFoodEmbeddingWorker.enqueue_all/0` first) — otherwise it exits
  cleanly without churning.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Food.ParserSuggestions

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    cursor = Map.get(args, "cursor", 0)

    case ParserSuggestions.generate_batch(cursor, limit: @batch_size) do
      {:ok, %{last_id: nil}} ->
        Logger.info("ParserSuggestionWorker: no more unresolved parses")
        :ok

      {:ok, %{inserted: inserted, batch: batch, last_id: last_id}} ->
        Logger.info(
          "ParserSuggestionWorker: batch=#{batch} inserted=#{inserted} cursor→#{last_id}"
        )

        %{"cursor" => last_id} |> new() |> Oban.insert!()
        :ok

      {:error, :embeddings_disabled} ->
        Logger.info("ParserSuggestionWorker: embeddings disabled — skipping")
        :ok
    end
  end

  @doc "Kick off a full suggestion pass from the start of the corpus."
  def enqueue do
    %{"cursor" => 0} |> new() |> Oban.insert()
  end
end
