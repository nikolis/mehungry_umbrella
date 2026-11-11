defmodule Mehungry.CompoundPipeline.DerivationWorker do
  @moduledoc """
  Derives species↔compound candidates from evidence, one batch per run tick.

  A single job threads a `run_id` (and an `offset`) through a self-re-enqueueing
  chain, deriving/refreshing a window of `CompoundPipeline.evidence_pairs/0` each
  tick, auto-promoting any that clear the threshold, and refreshing the run's
  progress — until the offset runs past the evidence pairs, then marking the run
  `completed`.

  Derivation is pure DB work (no external API), so there is no rate-limit/transient
  path: an empty batch means done. Re-derivation is idempotent (candidate upsert on
  the natural key, never touching a promoted/rejected status), so an Oban retry of a
  crashed tick is safe.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.CompoundPipeline.Candidates
  alias Mehungry.CompoundPipeline.DerivationRuns

  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    run_id = Map.get(args, "run_id")
    offset = Map.get(args, "offset", 0)
    DerivationRuns.mark_processing(run_id)

    case Candidates.derive_candidates_batch(offset, @batch_size) do
      {0, _promoted} ->
        Logger.info("CompoundPipeline.DerivationWorker: all evidence pairs derived")

        DerivationRuns.mark_completed(
          run_id,
          Candidates.candidate_derivation_progress()
        )

        :ok

      {_derived, promoted} ->
        DerivationRuns.bump_promoted(run_id, promoted)

        DerivationRuns.update_progress(
          run_id,
          Candidates.candidate_derivation_progress()
        )

        enqueue_next_batch(run_id, offset + @batch_size)
        :ok
    end
  end

  defp enqueue_next_batch(run_id, offset) do
    %{"run_id" => run_id, "offset" => offset} |> new() |> Oban.insert!()
  end
end
