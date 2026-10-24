defmodule Mehungry.Health.ClearRecommendationsTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.{Food, Health, Literature, Repo}
  alias Mehungry.Health.RecommendationCandidates, as: RC

  alias Mehungry.Health.{
    CompoundRecommendation,
    CompoundRecommendationCandidate,
    ConditionStateRecommendation,
    NutrientRecommendation
  }

  setup do
    {:ok, condition} = Health.create_condition(%{name: "Test Condition"})
    {:ok, compound} = Food.upsert_compound(%{name: "Test Compound", compound_type: "other"})
    %{condition: condition, compound: compound}
  end

  defp seed_advice_layer(ctx) do
    # A promoted compound recommendation.
    {:ok, _} =
      Health.add_recommendation(ctx.condition.id, ctx.compound.id, %{
        recommendation: "avoid",
        severity: "moderate",
        evidence_level: "moderate",
        source: "manual",
        source_reference: %{"label" => "t", "url" => "https://x"}
      })

    # A promoted nutrient recommendation.
    {:ok, _} =
      Health.add_nutrient_recommendation(ctx.condition.id, "Fiber", %{
        recommendation: "encourage",
        severity: "low",
        evidence_level: "moderate",
        source: "manual",
        source_reference: %{"label" => "t", "url" => "https://x"}
      })

    # A phase-aware (state) recommendation.
    {:ok, _} =
      Health.upsert_state_recommendation(%{
        condition_id: ctx.condition.id,
        compound_id: ctx.compound.id,
        recommendation: "avoid",
        source: "manual",
        source_reference: %{"label" => "t", "url" => "https://x"}
      })

    # A pending review-queue candidate (derived from a literature relation).
    {:ok, study} = Literature.upsert_study(%{pmid: 777_111, title: "s"})

    {:ok, _} =
      Literature.upsert_entity_relation(%{
        study_id: study.id,
        type: "Positive_Correlation",
        score: 0.9,
        entity1_type: "chemical",
        entity1_identifier: "mesh:C1",
        entity2_type: "disease",
        entity2_identifier: "mesh:D1",
        compound_id: ctx.compound.id,
        condition_id: ctx.condition.id
      })

    {:ok, _} = RC.derive_candidate(ctx.condition.id, ctx.compound.id)
  end

  test "deletes every candidate and promoted recommendation, returns counts", ctx do
    seed_advice_layer(ctx)

    assert Repo.aggregate(CompoundRecommendation, :count) == 1
    assert Repo.aggregate(NutrientRecommendation, :count) == 1
    assert Repo.aggregate(ConditionStateRecommendation, :count) == 1
    assert Repo.aggregate(CompoundRecommendationCandidate, :count) == 1

    assert {:ok, %{candidates: 1, recommendations: 3}} =
             Health.clear_all_recommendations_and_candidates()

    assert Repo.aggregate(CompoundRecommendation, :count) == 0
    assert Repo.aggregate(NutrientRecommendation, :count) == 0
    assert Repo.aggregate(ConditionStateRecommendation, :count) == 0
    assert Repo.aggregate(CompoundRecommendationCandidate, :count) == 0
  end

  test "leaves conditions and compounds intact", ctx do
    seed_advice_layer(ctx)
    {:ok, _} = Health.clear_all_recommendations_and_candidates()

    assert Health.get_condition_by_name("Test Condition").id == ctx.condition.id
    assert Repo.get(Mehungry.Food.Compound, ctx.compound.id)
  end

  test "is a no-op on an empty advice layer", _ctx do
    assert {:ok, %{candidates: 0, recommendations: 0}} =
             Health.clear_all_recommendations_and_candidates()
  end
end
