defmodule Mehungry.ObanWorkers.RecommendationCandidateDerivationWorker do
  @moduledoc """
  Derives condition↔compound recommendation candidates from `study_entity_relations`,
  one batch per run tick.

  Mirrors `CompoundCandidateDerivationWorker`: a single job threads a `run_id` (and an
  `offset`) through a self-re-enqueueing chain, deriving/refreshing a window of
  `RecommendationCandidates` relation pairs each tick and refreshing the run's
  progress — until the offset runs past the pairs, then marking the run `completed`.

  Derivation is pure DB work (no external API) and never auto-promotes, so there is no
  rate-limit path and no promotion count: an empty batch means done. Re-derivation is
  idempotent (candidate upsert on the natural key, never touching a decided status), so
  an Oban retry of a crashed tick is safe.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Health.RecommendationCandidates
  alias Mehungry.Health.RecommendationDerivationRuns

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    offset = Map.get(args, "offset", 0)
    RecommendationDerivationRuns.mark_processing(run_id)

    case RecommendationCandidates.derive_candidates_batch(offset, @batch_size) do
      {0, _} ->
        Logger.info("RecommendationCandidateDerivationWorker: all relation pairs derived")

        RecommendationDerivationRuns.mark_completed(
          run_id,
          RecommendationCandidates.recommendation_derivation_progress()
        )

        :ok

      {_derived, _} ->
        RecommendationDerivationRuns.update_progress(
          run_id,
          RecommendationCandidates.recommendation_derivation_progress()
        )

        enqueue_next_batch(run_id, offset + @batch_size)
        :ok
    end
  end

  defp enqueue_next_batch(run_id, offset) do
    %{"run_id" => run_id, "offset" => offset} |> new() |> Oban.insert!()
  end
end
