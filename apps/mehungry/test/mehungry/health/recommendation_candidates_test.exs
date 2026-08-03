defmodule Mehungry.Health.RecommendationCandidatesTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.{Food, Health, Literature, Repo}
  alias Mehungry.Food.Compounds
  alias Mehungry.Health.RecommendationCandidates, as: RC
  alias Mehungry.Literature.StudyEntityRelation

  setup do
    {:ok, condition} = Health.create_condition(%{name: "Type 2 Diabetes Mellitus"})
    {:ok, compound} = Food.upsert_compound(%{name: "D-Fructose", compound_type: "other"})
    {:ok, study} = Literature.upsert_study(%{pmid: 555_001, title: "s"})
    %{condition: condition, compound: compound, study: study}
  end

  # Insert a resolved relation directly (endpoint resolution is covered separately).
  defp relation!(ctx, type, identifier_suffix) do
    {:ok, _} =
      Literature.upsert_entity_relation(%{
        study_id: ctx.study.id,
        type: type,
        score: 0.9,
        entity1_type: "chemical",
        entity1_identifier: "mesh:C#{identifier_suffix}",
        entity2_type: "disease",
        entity2_identifier: "mesh:D#{identifier_suffix}",
        compound_id: ctx.compound.id,
        condition_id: ctx.condition.id
      })
  end

  test "positive correlation → suggests avoid; candidate enters the review queue", ctx do
    relation!(ctx, "Positive_Correlation", "1")

    assert {:ok, %{candidate: cand, promoted: false}} =
             RC.derive_candidate(ctx.condition.id, ctx.compound.id)

    assert cand.suggested_recommendation == "avoid"
    assert cand.relation_counts["positive"] == 1
    assert cand.study_count == 1
    assert cand.evidence_score > 0.0

    assert [pending] = RC.list_pending_candidates()
    assert pending.id == cand.id
    assert pending.condition.id == ctx.condition.id
    assert pending.compound.id == ctx.compound.id
  end

  test "negative correlation → suggests encourage", ctx do
    relation!(ctx, "Negative_Correlation", "2")
    {:ok, %{candidate: cand}} = RC.derive_candidate(ctx.condition.id, ctx.compound.id)
    assert cand.suggested_recommendation == "encourage"
  end

  test "derivation never auto-promotes", ctx do
    relation!(ctx, "Positive_Correlation", "3")
    {:ok, %{promoted: promoted}} = RC.derive_candidate(ctx.condition.id, ctx.compound.id)
    refute promoted
    assert Health.recommendations_for_condition(ctx.condition.id) == []
  end

  test "promotion writes a literature-sourced recommendation; re-derivation preserves status",
       ctx do
    relation!(ctx, "Positive_Correlation", "4")
    {:ok, %{candidate: cand}} = RC.derive_candidate(ctx.condition.id, ctx.compound.id)

    assert {:ok, promoted} =
             RC.promote_candidate(cand.id, %{recommendation: "avoid", severity: "moderate"})

    assert promoted.status == "promoted"
    assert promoted.promoted_recommendation_id

    assert [rec] = Health.recommendations_for_condition(ctx.condition.id)
    assert rec.recommendation == "avoid"
    assert rec.severity == "moderate"
    assert rec.source == "literature"
    assert rec.compound.id == ctx.compound.id

    # A later re-derivation refreshes evidence but must not resurrect a decided candidate.
    {:ok, _} = RC.derive_candidate(ctx.condition.id, ctx.compound.id)
    assert RC.list_pending_candidates() == []
  end

  test "Literature.persist_study_relations resolves both endpoints from identifiers", ctx do
    {:ok, _} =
      Compounds.upsert_compound_identifier(%{
        compound_id: ctx.compound.id,
        namespace: "mesh",
        identifier: "D005632",
        source: "test"
      })

    {:ok, _} =
      Health.upsert_condition_identifier(%{
        condition_id: ctx.condition.id,
        namespace: "mesh",
        identifier: "D003924",
        source: "test"
      })

    rel = %{
      type: "Positive_Correlation",
      score: 0.9,
      entity1_type: "chemical",
      entity1_identifier: "mesh:D005632",
      entity1_name: "Fructose",
      entity2_type: "disease",
      entity2_identifier: "mesh:D003924",
      entity2_name: "Diabetes Mellitus Type 2"
    }

    assert 1 == Literature.persist_study_relations(ctx.study.id, [rel])

    [row] = Repo.all(StudyEntityRelation)
    assert row.compound_id == ctx.compound.id
    assert row.condition_id == ctx.condition.id
  end
end
