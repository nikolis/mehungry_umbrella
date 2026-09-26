defmodule Mehungry.ObanWorkers.CompoundFactAuditWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.CompoundCandidates
  alias Mehungry.Food.SpeciesCompoundRelationship
  alias Mehungry.Literature
  alias Mehungry.ObanWorkers.CompoundFactAuditWorker, as: Worker
  alias Mehungry.Repo

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :compound_plausibility_stub) end)

    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    %{spinach: spinach, oxalate: oxalate, species: species}
  end

  defp cooccur(ingredient, compound) do
    pmid = System.unique_integer([:positive])
    {:ok, study} = Literature.upsert_study(%{pmid: pmid, title: "s#{pmid}"})

    {:ok, _} =
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: ingredient.id,
        search_term: "term-#{pmid}"
      })

    {:ok, _} =
      Literature.upsert_entity_mention(%{
        study_id: study.id,
        entity_type: "chemical",
        normalized_identifier: "mesh:D#{pmid}",
        text_span: "oxalic acid",
        offset: 1,
        compound_id: compound.id
      })
  end

  # A pre-gate promoted literature fact (backing candidate has no verdict).
  defp ungated_fact(ctx) do
    for _ <- 1..5, do: cooccur(ctx.spinach, ctx.oxalate)

    {:ok, %{candidate: cand, promoted: true}} =
      CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id, skip_plausibility: true)

    cand
  end

  test "flags an implausible fact, leaves it in place, and chains a follow-up", ctx do
    cand = ungated_fact(ctx)

    Application.put_env(:mehungry, :compound_plausibility_stub, fn _s, _c, _st ->
      {:ok, %{verdict: :implausible, reason: "solvent"}}
    end)

    # The tick audits the one fact (progress) → flags it → chains a follow-up.
    assert :ok = perform_job(Worker, %{})
    assert [flagged] = CompoundCandidates.list_flagged_facts()
    assert flagged.id == cand.id
    # The fact still exists — audit only flags, never deletes.
    assert Repo.get(SpeciesCompoundRelationship, cand.promoted_relationship_id)
    assert_enqueued(worker: Worker)
  end

  test "stops chaining once every fact has a verdict", ctx do
    ungated_fact(ctx)
    # Pre-audit it (default stub → :plausible) so no un-audited fact remains.
    assert {1, 0} = CompoundCandidates.audit_promoted_facts_batch(10)

    assert :ok = perform_job(Worker, %{})
    refute_enqueued(worker: Worker)
  end

  test "no un-audited facts → completes without chaining", _ctx do
    assert :ok = perform_job(Worker, %{})
    refute_enqueued(worker: Worker)
  end
end
