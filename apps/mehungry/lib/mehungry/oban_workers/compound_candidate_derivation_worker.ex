defmodule Mehungry.ObanWorkers.CompoundCandidateDerivationWorker do
  @moduledoc """
  Derives ingredient↔compound candidates from evidence, one batch per run tick.

  Mirrors `IngredientIdentityResolutionWorker`: a single job threads a `run_id`
  (and an `offset`) through a self-re-enqueueing chain, deriving/refreshing a
  window of `Food.evidence_pairs/0` each tick, auto-promoting any that clear the
  threshold, and refreshing the run's progress — until the offset runs past the
  evidence pairs, then marking the run `completed`.

  Derivation is pure DB work (no external API), so there is no rate-limit/transient
  path: an empty batch means done. Re-derivation is idempotent (candidate upsert on
  the natural key, never touching a promoted/rejected status), so an Oban retry of a
  crashed tick is safe.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Food.CandidateDerivationRuns
  alias Mehungry.Food.CompoundCandidates

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    offset = Map.get(args, "offset", 0)
    CandidateDerivationRuns.mark_processing(run_id)

    case CompoundCandidates.derive_candidates_batch(offset, @batch_size) do
      {0, _promoted} ->
        Logger.info("CompoundCandidateDerivationWorker: all evidence pairs derived")

        CandidateDerivationRuns.mark_completed(
          run_id,
          CompoundCandidates.candidate_derivation_progress()
        )

        :ok

      {_derived, promoted} ->
        CandidateDerivationRuns.bump_promoted(run_id, promoted)

        CandidateDerivationRuns.update_progress(
          run_id,
          CompoundCandidates.candidate_derivation_progress()
        )

        enqueue_next_batch(run_id, offset + @batch_size)
        :ok
    end
  end

  defp enqueue_next_batch(run_id, offset) do
    %{"run_id" => run_id, "offset" => offset} |> new() |> Oban.insert!()
  end
end
