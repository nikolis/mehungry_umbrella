defmodule Mehungry.ObanWorkers.CompoundFactAuditWorker do
  @moduledoc """
  Re-runs the plausibility gate over already-promoted `literature`
  `SpeciesCompoundRelationship` facts that predate the gate (their backing candidate
  has no `plausibility_verdict`). Each implausible fact is **flagged** — the verdict
  is recorded on the candidate so it surfaces in the "Flagged facts" review list on
  `/professional/compound-candidates`. The audit never deletes a fact; a human
  decides via Undo or "Non-dietary".

  Mirrors `CompoundCandidateDerivationWorker`'s self-re-enqueueing chain, but each
  tick makes LLM calls, so batches are small and the terminating condition is
  progress-based: a tick that audits at least one fact enqueues the next; a tick that
  audits none — because nothing is left, OR because the judge is unavailable and every
  call errored — stops. Un-audited facts (judge errors) simply remain for a later
  manual re-run, so a transient AI outage can't wedge the chain.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  alias Mehungry.Food.CompoundCandidates

  # LLM calls per tick — keep modest.
  @batch_size 20

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case CompoundCandidates.audit_promoted_facts_batch(@batch_size) do
      {0, _flagged} ->
        Logger.info("CompoundFactAuditWorker: audit pass complete (no further progress)")
        :ok

      {audited, flagged} ->
        Logger.info("CompoundFactAuditWorker: audited #{audited} fact(s), flagged #{flagged}")
        %{} |> new() |> Oban.insert!()
        :ok
    end
  end
end
