defmodule Mehungry.CompoundPipeline do
  @moduledoc """
  Facade for the **compound pipeline** — the isolated, admin-run curation flow that
  turns accumulated evidence into curated `FoundementalFoodSpecies`↔`Compound` facts.

  It has a clear beginning, steps, and an outcome:

      ① Evidence   — literature co-occurrence (frozen corpus) + species measurements +
                     manual import  (read from `Mehungry.Food` / `Mehungry.Literature`)
      ② Derive     — score each `{species, compound}` pair (noisy-OR) into a candidate
      ③ Gate       — two credibility filters on auto-promotion:
                     curated `Compound.dietary_relevance` + an LLM plausibility check
      ④ Review     — an admin promotes / rejects the rest
      ⑤ Outcome    — curated `Food.SpeciesCompoundRelationship` facts, which `Health`
                     advice and the `/foods` filter read (and which seed targeted
                     literature search terms)

  This context owns ②–④; the *facts* it writes in ⑤ stay in `Mehungry.Food`
  (`Food.SpeciesCompounds`) as the shared output sink. Dependency direction is
  one-way: `CompoundPipeline → Food`. Implementation lives in the sub-modules:

    * `CompoundPipeline.Candidates` — derive, score, the gate, promotion/review, queries
    * `CompoundPipeline.Plausibility` — the LLM "reality check" (behind a config seam)
    * `CompoundPipeline.DerivationRuns` — run lifecycle + PubSub progress
    * `CompoundPipeline.{DerivationWorker, FactAuditWorker}` — the `:imports` batch chains

  See `docs/implementation/compound_pipeline.md`.
  """

  alias Mehungry.CompoundPipeline.Candidates
  alias Mehungry.CompoundPipeline.DerivationRuns

  # ── Pipeline control + progress ────────────────────────────────────────────

  defdelegate enqueue_candidate_derivation(), to: Candidates
  defdelegate candidate_derivation_progress(), to: Candidates
  defdelegate evidence_pairs(), to: Candidates
  defdelegate count_evidence_pairs(), to: Candidates
  defdelegate runs_topic(), to: DerivationRuns, as: :topic
  defdelegate latest_run(), to: DerivationRuns

  # ── Derivation + scoring ───────────────────────────────────────────────────

  defdelegate derive_candidate(species_id, compound_id), to: Candidates
  defdelegate derive_candidates_batch(offset, limit), to: Candidates
  defdelegate score_candidate(species_id, compound_id), to: Candidates

  # ── Review queue + promotion ───────────────────────────────────────────────

  defdelegate list_pending_candidates(opts \\ []), to: Candidates
  defdelegate list_candidates_for_species(species_id), to: Candidates
  defdelegate list_candidate_studies(candidate_id), to: Candidates
  defdelegate get_candidate!(id), to: Candidates
  defdelegate promote_candidate(candidate), to: Candidates
  defdelegate reject_candidate(candidate), to: Candidates
  defdelegate unpromote_relationship(relationship_id), to: Candidates
  defdelegate import_manual_candidate(species_id, compound_id, attrs), to: Candidates

  # ── Credibility gate (non-dietary compounds) ───────────────────────────────

  defdelegate non_dietary_compound_names(), to: Candidates
  defdelegate purge_non_dietary(), to: Candidates

  # ── Audit of already-promoted facts ────────────────────────────────────────

  defdelegate enqueue_fact_audit(), to: Candidates
  defdelegate audit_promoted_facts_batch(limit), to: Candidates
  defdelegate count_promoted_facts_to_audit(), to: Candidates
  defdelegate list_flagged_facts(opts \\ []), to: Candidates
end
