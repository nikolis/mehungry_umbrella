defmodule Mehungry.Health.ConditionRecCandidatesTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.{Food, Health, Literature}
  alias Mehungry.Health.ConditionRecCandidates, as: C

  setup do
    {:ok, condition} = Health.create_condition(%{name: "Ulcerative Colitis"})

    {:ok, flare} =
      Health.upsert_state(%{
        condition_id: condition.id,
        name: "Active Flare",
        slug: "active_flare",
        is_default: true,
        position: 0
      })

    {:ok, remission} =
      Health.upsert_state(%{
        condition_id: condition.id,
        name: "Remission",
        slug: "remission",
        position: 1
      })

    {:ok, compound} = Food.upsert_compound(%{name: "Curcumin", compound_type: "other"})
    {:ok, study} = Literature.upsert_study(%{pmid: 700_001, title: "UC fiber study"})

    %{condition: condition, flare: flare, remission: remission, compound: compound, study: study}
  end

  describe "upsert_candidate/1 — grounding + idempotency" do
    test "resolves a nutrient term, the state slug, and links the study", ctx do
      {:ok, cand} =
        C.upsert_candidate(%{
          "study_id" => ctx.study.id,
          "condition_id" => ctx.condition.id,
          "raw_term" => "insoluble fiber",
          "target_kind" => "nutrient",
          "direction" => "avoid",
          "condition_state_slug" => "active_flare",
          "severity" => "high",
          "confidence" => 0.8,
          "evidence_snippet" => "insoluble fiber worsened flares"
        })

      assert cand.condition_state_id == ctx.flare.id
      assert cand.nutrient_name == "Fiber"
      assert cand.suggested_recommendation == "avoid"
      assert cand.status == "pending"
      assert cand.study_count == 1
    end

    test "resolves a known compound by name; unknown compounds stay unresolved", ctx do
      {:ok, resolved} =
        C.upsert_candidate(%{
          "study_id" => ctx.study.id,
          "condition_id" => ctx.condition.id,
          "raw_term" => "Curcumin",
          "target_kind" => "compound",
          "direction" => "encourage",
          "condition_state_slug" => "remission"
        })

      assert resolved.compound_id == ctx.compound.id

      {:ok, unknown} =
        C.upsert_candidate(%{
          "study_id" => ctx.study.id,
          "condition_id" => ctx.condition.id,
          "raw_term" => "Unobtainium",
          "target_kind" => "compound",
          "direction" => "encourage",
          "condition_state_slug" => "remission"
        })

      assert is_nil(unknown.compound_id)
      assert unknown.raw_term == "Unobtainium"
    end

    test "re-upserting the same finding is idempotent (dedup_key)", ctx do
      attrs = %{
        "study_id" => ctx.study.id,
        "condition_id" => ctx.condition.id,
        "raw_term" => "low-residue",
        "target_kind" => "food_pattern",
        "direction" => "encourage",
        "condition_state_slug" => "active_flare"
      }

      {:ok, first} = C.upsert_candidate(attrs)
      {:ok, second} = C.upsert_candidate(Map.put(attrs, "confidence", 0.95))

      assert first.id == second.id
      assert length(C.list_pending_candidates()) == 1
    end
  end

  describe "extraction pending set + termination ledger" do
    test "a crawled pair is pending until an attempt is recorded", ctx do
      {:ok, _} =
        Literature.link_study_condition(%{
          study_id: ctx.study.id,
          condition_id: ctx.condition.id,
          search_term: "Ulcerative Colitis diet"
        })

      assert [pair] = C.list_pending_extraction(10)
      assert pair.study_id == ctx.study.id and pair.condition_id == ctx.condition.id

      {:ok, _} =
        C.record_extraction_attempt(%{study_id: ctx.study.id, condition_id: ctx.condition.id})

      assert C.list_pending_extraction(10) == []
    end
  end

  describe "promote_candidate/2 — writes the decoupled store, frozen provenance" do
    test "promotes to a phase-tagged recommendation and freezes studies", ctx do
      {:ok, cand} =
        C.upsert_candidate(%{
          "study_id" => ctx.study.id,
          "condition_id" => ctx.condition.id,
          "raw_term" => "insoluble fiber",
          "target_kind" => "nutrient",
          "direction" => "avoid",
          "condition_state_slug" => "active_flare"
        })

      {:ok, rec} = C.promote_candidate(cand.id, %{"recommendation" => "avoid", "severity" => "high"})

      assert rec.source == "literature"
      assert rec.condition_state_id == ctx.flare.id
      assert rec.nutrient_name == "Fiber"

      rec = Repo.preload(rec, :studies)
      assert Enum.map(rec.studies, & &1.id) == [ctx.study.id]

      assert C.get_candidate!(cand.id).status == "promoted"
    end

    test "read seam returns the phase's rows plus general, excluding other phases", ctx do
      {:ok, flare_cand} =
        C.upsert_candidate(%{
          "study_id" => ctx.study.id,
          "condition_id" => ctx.condition.id,
          "raw_term" => "insoluble fiber",
          "target_kind" => "nutrient",
          "direction" => "avoid",
          "condition_state_slug" => "active_flare"
        })

      {:ok, _} = C.promote_candidate(flare_cand.id, %{"recommendation" => "avoid"})

      assert length(Health.state_recommendations_for_condition(ctx.condition.id, ctx.flare.id)) == 1
      assert Health.state_recommendations_for_condition(ctx.condition.id, ctx.remission.id) == []
      assert Health.state_recommendations_for_condition(ctx.condition.id, nil) == []
    end
  end

  test "reject_candidate/1 removes it from the queue", ctx do
    {:ok, cand} =
      C.upsert_candidate(%{
        "study_id" => ctx.study.id,
        "condition_id" => ctx.condition.id,
        "raw_term" => "nuts",
        "target_kind" => "food_pattern",
        "direction" => "avoid",
        "condition_state_slug" => "active_flare"
      })

    {:ok, _} = C.reject_candidate(cand.id)
    assert C.list_pending_candidates() == []
    assert C.get_candidate!(cand.id).status == "rejected"
  end
end
