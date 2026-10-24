defmodule Mehungry.Health.ClaimRulesTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Health, Literature, MealBlueprints}
  alias Mehungry.Health.ClaimRules

  # A `/analyze` response for `pmid` with the given claim list (mirrors the
  # extractor shape; see Mehungry.Extractor.ClientStub).
  defp response(pmid, claims) do
    %{
      "run" => %{"synthesis_version" => "0.1.0"},
      "papers" => [%{"pmid" => to_string(pmid), "status" => "included"}],
      "paper_claims" => [
        %{"pmid" => to_string(pmid), "claims_list" => claims}
      ]
    }
  end

  defp claim(subject, predicate, object, opts \\ []) do
    disease_state = Keyword.get(opts, :disease_state)

    qualifiers =
      if disease_state,
        do: [%{"qualifier_type" => "disease_state", "value_text" => disease_state}],
        else: []

    %{
      "claim_id" => "#{subject}-#{predicate}-#{object}-#{disease_state}",
      "subject_name" => subject,
      "object_name" => object,
      "predicate" => predicate,
      "polarity" => Keyword.get(opts, :polarity, "positive"),
      "certainty" => Keyword.get(opts, :certainty, "asserted"),
      "qualifiers" => qualifiers,
      "evidence" => [%{"quoted_text" => "#{subject} #{predicate} #{object}."}]
    }
  end

  # Seed a condition, a study linked to it, and store an analysis for that study.
  defp seed(condition_attrs, pmid, claims) do
    {:ok, condition} = Health.create_condition(condition_attrs)
    {:ok, study} = Literature.upsert_study(%{pmid: pmid, title: "p#{pmid}"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "#{condition.name} diet"
      })

    {:ok, _} = Literature.store_analysis_response(response(pmid, claims))
    {condition, study}
  end

  test "derives an avoid rule for a known compound with a harmful predicate" do
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Kidney Stones #{System.unique_integer([:positive])}"}, 880_001, [
        claim("Oxalate", "increases", "kidney stones")
      ])

    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.direction == "avoid"
    assert rule.kind == :compound
    assert rule.compound_id == oxalate.id
    assert rule.already_recommended? == false

    # Freshly stored claims are unassigned, so they don't feed the count yet.
    assert rule.paper_count == 0

    # The rule carries the verbatim API claim(s) that back it, untouched.
    assert [%{pmid: 880_001, position: nil, claim: c}] = rule.sources
    assert c["predicate"] == "increases"
    assert c["subject_name"] == "Oxalate"
    assert [%{"quoted_text" => _}] = c["evidence"]
    refute Map.has_key?(c, "__pmid__")
  end

  test "excludes hedged claims" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Gout #{System.unique_integer([:positive])}"}, 880_002, [
        claim("Oxalate", "increases", "gout", certainty: "hedged")
      ])

    assert ClaimRules.rules_for_condition(condition.id) == []
  end

  test "flags a rule already covered by an existing recommendation" do
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Stones #{System.unique_integer([:positive])}"}, 880_003, [
        claim("Oxalate", "increases", "stones")
      ])

    {:ok, _} =
      Health.add_recommendation(condition.id, oxalate.id, %{
        recommendation: "avoid",
        source: "guideline",
        source_reference: %{"label" => "g", "url" => "https://example.org"}
      })

    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.already_recommended? == true
  end

  test "an unknown predicate yields a review direction" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "IBS #{System.unique_integer([:positive])}"}, 880_004, [
        claim("Oxalate", "studied_in", "IBS")
      ])

    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.direction == "review"
  end

  test "only food_related claims feed the count; others stay visible" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, study} =
      seed(%{name: "Stones #{System.unique_integer([:positive])}"}, 882_001, [
        claim("Oxalate", "increases", "stones")
      ])

    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.paper_count == 0
    assert [%{position: nil, claim: c}] = rule.sources
    claim_id = c["claim_id"]

    # Marking it food_related makes it count.
    {:ok, _} = Literature.set_claim_position(study.id, claim_id, "food_related")
    assert [%{paper_count: 1, sources: [%{position: "food_related"}]}] =
             ClaimRules.rules_for_condition(condition.id)

    # Marking it wrong drops it from the count but keeps it listed (re-categorisable).
    {:ok, _} = Literature.set_claim_position(study.id, claim_id, "wrong")
    assert [%{paper_count: 0, sources: [%{position: "wrong"}]}] =
             ClaimRules.rules_for_condition(condition.id)
  end

  test "splits one suggestion per existing phase (phase is part of the identity)" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Colitis #{System.unique_integer([:positive])}"}, 883_001, [
        claim("Oxalate", "increases", "colitis", disease_state: "active flare"),
        claim("Oxalate", "increases", "colitis", disease_state: "remission"),
        claim("Oxalate", "increases", "colitis")
      ])

    # The condition actually has these phases, so the claims split along them.
    {:ok, _} = Health.upsert_state(%{condition_id: condition.id, name: "Active Flare", slug: "active_flare"})
    {:ok, _} = Health.upsert_state(%{condition_id: condition.id, name: "Remission", slug: "remission"})

    # Same entity + direction, but three distinct phases → three suggestions
    # (Active Flare, Remission, general), each with its own verify_key.
    rules = ClaimRules.rules_for_condition(condition.id)
    assert length(rules) == 3

    states = rules |> Enum.map(& &1.disease_state) |> Enum.sort_by(&(&1 || ""))
    assert states == [nil, "Active Flare", "Remission"]

    assert rules |> Enum.map(& &1.verify_key) |> Enum.uniq() |> length() == 3

    # Each carries its own phase label (general has none).
    for rule <- rules do
      case rule.disease_state do
        nil -> assert rule.disease_states == []
        ds -> assert rule.disease_states == [ds]
      end
    end
  end

  test "a disease state with no matching phase is treated as general advice" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Colitis #{System.unique_integer([:positive])}"}, 883_002, [
        claim("Oxalate", "increases", "colitis", disease_state: "active flare"),
        claim("Oxalate", "increases", "colitis")
      ])

    # No phases exist on this condition, so the "active flare" claim is NOT split out
    # (we never invent a phase) — both claims collapse into one general suggestion.
    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.state_id == nil
    assert rule.disease_state == nil
    assert rule.disease_states == []
  end

  test "merges synonymous disease states (flare / active disease) onto the matching phase" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Colitis #{System.unique_integer([:positive])}"}, 883_020, [
        claim("Oxalate", "increases", "colitis", disease_state: "flare"),
        claim("Oxalate", "increases", "colitis", disease_state: "active disease"),
        claim("Oxalate", "increases", "colitis", disease_state: "Active Flares")
      ])

    {:ok, state} =
      Health.upsert_state(%{condition_id: condition.id, name: "Active Flare", slug: "active_flare"})

    # All three labels canonicalize to the condition's existing "Active Flare" phase →
    # a single suggestion scoped to it.
    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.state_id == state.id
    assert rule.disease_state == "Active Flare"
    assert rule.disease_states == ["Active Flare"]
  end

  test "a hedged claim counts once the admin marks it food_related" do
    {:ok, _} = Food.upsert_compound(%{name: "Insoluble fiber", compound_type: "other"})

    {condition, study} =
      seed(%{name: "IBS #{System.unique_integer([:positive])}"}, 883_010, [
        claim("Insoluble fiber", "worsens", "symptoms",
          certainty: "possible",
          disease_state: "flare"
        )
      ])

    # The condition has an "Active Flare" phase, which "flare" canonicalizes to.
    {:ok, _} = Health.upsert_state(%{condition_id: condition.id, name: "Active Flare", slug: "active_flare"})

    # Hedged + unassigned → dropped from rules (the auto-filter).
    assert ClaimRules.rules_for_condition(condition.id) == []

    # The admin vouches for it → it now forms a counted suggestion, flare label included.
    analysis = Literature.get_analysis_by_study_id(study.id)
    {:ok, _} = Literature.set_claim_position(study.id, hd(analysis.claims)["claim_id"], "food_related")

    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.direction == "avoid"
    assert rule.paper_count == 1
    # "flare" canonicalizes to the existing "Active Flare" phase.
    assert rule.disease_states == ["Active Flare"]
  end

  test "annotate_analysis layers a __derived__ map onto each claim without touching API fields" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    resp =
      response(881_001, [
        claim("Oxalate", "increases", "stones"),
        claim("Vague thing", "studied_in", "stones", certainty: "hedged")
      ])

    annotated = ClaimRules.annotate_analysis(resp)
    [pc] = annotated["paper_claims"]
    [first, second] = pc["claims_list"]

    # Extractor fields are untouched.
    assert first["predicate"] == "increases"
    assert first["subject_name"] == "Oxalate"

    # App-derived layer is added under a private key.
    assert first["__derived__"].direction == "avoid"
    assert first["__derived__"].kind == :compound
    assert first["__derived__"].used_in_rules? == true

    # The hedged claim is annotated too, but flagged as not rule-usable.
    assert second["__derived__"].direction == "review"
    assert second["__derived__"].used_in_rules? == false
  end

  describe "verify_suggestion/3 (promote into the public advice layer)" do
    test "promotes a compound suggestion into a literature recommendation, freezing citations" do
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {condition, study} =
        seed(%{name: "Stones #{System.unique_integer([:positive])}"}, 884_001, [
          claim("Oxalate", "increases", "stones")
        ])

      {:ok, _} =
        Literature.set_claim_position(
          study.id,
          "Oxalate-increases-stones-",
          "food_related"
        )

      [rule] = ClaimRules.rules_for_condition(condition.id)
      assert rule.already_recommended? == false

      assert {:ok, rec} = ClaimRules.verify_suggestion(condition.id, rule, %{severity: "moderate"})
      assert rec.source == "literature"
      assert rec.recommendation == "avoid"
      assert rec.compound_id == oxalate.id

      # It now reads back as a curated recommendation on the condition.
      assert [%{compound_id: cid}] = Health.recommendations_for_condition(condition.id)
      assert cid == oxalate.id

      # Re-derivation now flags the suggestion as already covered (verify control hidden).
      assert [%{already_recommended?: true}] = ClaimRules.rules_for_condition(condition.id)

      # The backing study is frozen on as a citation.
      assert Mehungry.Repo.aggregate(
               from(s in Mehungry.Health.CompoundRecommendationStudy,
                 where: s.recommendation_id == ^rec.id
               ),
               :count
             ) == 1
    end

    test "honors the admin's confirmed direction over the suggestion's own" do
      {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {condition, study} =
        seed(%{name: "Gout #{System.unique_integer([:positive])}"}, 884_002, [
          claim("Oxalate", "increases", "gout")
        ])

      {:ok, _} = Literature.set_claim_position(study.id, "Oxalate-increases-gout-", "food_related")
      [rule] = ClaimRules.rules_for_condition(condition.id)
      assert rule.direction == "avoid"

      assert {:ok, rec} =
               ClaimRules.verify_suggestion(condition.id, rule, %{recommendation: "limit"})

      assert rec.recommendation == "limit"
    end

    test "promotes a nutrient suggestion into a nutrient recommendation" do
      # "Fiber, total dietary" is a canonical NutrientTargets label.
      {condition, study} =
        seed(%{name: "Constipation #{System.unique_integer([:positive])}"}, 884_003, [
          claim("Fiber", "improves", "constipation")
        ])

      {:ok, _} =
        Literature.set_claim_position(study.id, "Fiber-improves-constipation-", "food_related")

      rules = ClaimRules.rules_for_condition(condition.id)
      rule = Enum.find(rules, &(&1.kind == :nutrient))
      assert rule, "expected Fiber to resolve to a nutrient suggestion"

      assert {:ok, rec} = ClaimRules.verify_suggestion(condition.id, rule, %{})
      assert rec.source == "literature"
      assert [_] = Health.nutrient_recommendations_for_condition(condition.id)
    end

    test "verified_as reflects the module's own recommendation and drives recall" do
      {:ok, _oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {condition, study} =
        seed(%{name: "Stones #{System.unique_integer([:positive])}"}, 884_010, [
          claim("Oxalate", "increases", "stones")
        ])

      {:ok, _} = Literature.set_claim_position(study.id, "Oxalate-increases-stones-", "food_related")
      [rule] = ClaimRules.rules_for_condition(condition.id)
      assert rule.verified_as == nil

      {:ok, _} = ClaimRules.verify_suggestion(condition.id, rule, %{recommendation: "limit"})

      # Re-derivation now carries the verified direction (drives the select's value).
      [rule] = ClaimRules.rules_for_condition(condition.id)
      assert rule.verified_as == "limit"
      assert rule.already_recommended? == true

      # Recall removes the published recommendation; verified_as goes back to nil.
      assert {:ok, 1} = ClaimRules.recall_suggestion(condition.id, rule)
      assert Health.recommendations_for_condition(condition.id) == []
      assert [%{verified_as: nil}] = ClaimRules.rules_for_condition(condition.id)
    end

    test "recall leaves a differently-sourced recommendation untouched" do
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {condition, study} =
        seed(%{name: "Stones #{System.unique_integer([:positive])}"}, 884_011, [
          claim("Oxalate", "increases", "stones")
        ])

      {:ok, _} = Literature.set_claim_position(study.id, "Oxalate-increases-stones-", "food_related")

      # A hand-curated guideline recommendation for the same compound.
      {:ok, _} =
        Health.add_recommendation(condition.id, oxalate.id, %{
          recommendation: "avoid",
          source: "guideline",
          source_reference: %{"label" => "g", "url" => "https://example.org"}
        })

      [rule] = ClaimRules.rules_for_condition(condition.id)
      # The guideline rec is a different source, so it is not "verified by us".
      assert rule.verified_as == nil
      assert rule.already_recommended? == true

      # Recall is a no-op against the guideline rec (different source).
      assert {:ok, 0} = ClaimRules.recall_suggestion(condition.id, rule)
      assert [%{source: "guideline"}] = Health.recommendations_for_condition(condition.id)
    end

    test "publishes an unmatched suggestion as a free-text condition note" do
      {condition, study} =
        seed(%{name: "Mystery #{System.unique_integer([:positive])}"}, 884_004, [
          claim("Unobtanium", "improves", "mystery")
        ])

      {:ok, _} =
        Literature.set_claim_position(study.id, "Unobtanium-improves-mystery-", "food_related")

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert rule.kind == :unmatched

      # Verifying promotes it into the decoupled phase-aware store as a general
      # (all-phase) free-text note — never into the food-mapping compound layer.
      assert {:ok, rec} =
               ClaimRules.verify_suggestion(condition.id, rule, %{recommendation: "encourage"})

      assert rec.raw_food_term == "Unobtanium"
      assert rec.condition_state_id == nil
      assert rec.compound_id == nil
      assert rec.source == "literature"
      assert rec.recommendation == "encourage"
      assert Health.recommendations_for_condition(condition.id) == []

      # It surfaces on the condition page via the general-phase read, with its
      # backing study frozen as a citation.
      assert [note] = Health.state_recommendations_for_condition(condition.id, nil)
      assert note.raw_food_term == "Unobtanium"
      assert [%{pmid: 884_004}] = note.studies

      # Recall removes exactly that note again.
      assert {:ok, 1} = ClaimRules.recall_suggestion(condition.id, rule)
      assert Health.state_recommendations_for_condition(condition.id, nil) == []
    end

    test "a phase-scoped suggestion verifies into a state-scoped recommendation, independent of the general one" do
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {condition, study} =
        seed(%{name: "Colitis #{System.unique_integer([:positive])}"}, 884_020, [
          claim("Oxalate", "increases", "colitis", disease_state: "active flare"),
          claim("Oxalate", "increases", "colitis")
        ])

      # The phase must already exist — we never invent one.
      {:ok, state} =
        Health.upsert_state(%{condition_id: condition.id, name: "Active Flare", slug: "active_flare"})

      for value <- ["active flare", nil] do
        analysis = Literature.get_analysis_by_study_id(study.id)

        cid =
          Enum.find_value(analysis.claims, fn c ->
            s = (List.first(c["qualifiers"] || []) || %{})["value_text"]
            if s == value, do: c["claim_id"]
          end)

        {:ok, _} = Literature.set_claim_position(study.id, cid, "food_related")
      end

      rules = ClaimRules.rules_for_condition(condition.id)
      phase_rule = Enum.find(rules, &(&1.disease_state == "Active Flare"))
      general_rule = Enum.find(rules, &is_nil(&1.disease_state))

      # The phase-scoped one promotes into the decoupled store under the existing
      # "Active Flare" ConditionState — never into the general compound table.
      assert {:ok, rec} = ClaimRules.verify_suggestion(condition.id, phase_rule, %{})
      assert rec.compound_id == oxalate.id
      assert rec.condition_state_id == state.id
      assert Health.recommendations_for_condition(condition.id) == []

      # It shows under that phase on the condition page, and re-derivation marks it verified.
      assert [%{compound_id: cid}] =
               Health.state_recommendations_for_condition(condition.id, state.id)

      assert cid == oxalate.id

      rules = ClaimRules.rules_for_condition(condition.id)
      assert Enum.find(rules, &(&1.disease_state == "Active Flare")).verified_as == "avoid"
      # The general variant is untouched by the phase-scoped verification.
      assert Enum.find(rules, &is_nil(&1.disease_state)).verified_as == nil

      # The general one promotes into the compound table, still independent.
      assert {:ok, _} = ClaimRules.verify_suggestion(condition.id, general_rule, %{})
      assert [%{compound_id: general_cid}] = Health.recommendations_for_condition(condition.id)
      assert general_cid == oxalate.id

      # Recalling the phase-scoped one leaves the general one in place.
      assert {:ok, 1} = ClaimRules.recall_suggestion(condition.id, phase_rule)
      assert Health.state_recommendations_for_condition(condition.id, state.id) == []
      assert [_] = Health.recommendations_for_condition(condition.id)
    end
  end

  describe "species & blueprint matching" do
    test "matches a food species by name and publishes it as a condition food row" do
      {:ok, species} = Food.create_foundemental_species(%{name: "Spinach", scientific_name: "Spinacia oleracea"})

      {condition, study} =
        seed(%{name: "Anemia #{System.unique_integer([:positive])}"}, 885_001, [
          claim("Spinach", "improves", "anemia")
        ])

      {:ok, _} = Literature.set_claim_position(study.id, "Spinach-improves-anemia-", "food_related")

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert rule.kind == :species
      assert rule.species_id == species.id
      assert rule.direction == "encourage"

      assert {:ok, rec} = ClaimRules.verify_suggestion(condition.id, rule, %{})
      assert rec.species_id == species.id
      assert rec.condition_state_id == nil
      assert rec.source == "literature"

      # Surfaces as a food row via species_for_condition (no backing compound).
      rows = Health.species_for_condition(condition.id)
      assert Enum.any?(rows, &(&1.species.id == species.id and is_nil(&1.compound)))

      # Re-derivation flags it as already-published and reflects the direction.
      [rule2] = ClaimRules.rules_for_condition(condition.id)
      assert rule2.already_recommended? == true
      assert rule2.verified_as == "encourage"

      assert {:ok, 1} = ClaimRules.recall_suggestion(condition.id, rule2)
      assert Health.species_for_condition(condition.id) == []
    end

    test "a raw suggestion verified before the species existed still reads as accepted" do
      # Verify "Kale" while it is unknown → stored as a free-text note.
      {condition, study} =
        seed(%{name: "Anemia #{System.unique_integer([:positive])}"}, 885_010, [
          claim("Kale", "improves", "anemia")
        ])

      {:ok, _} = Literature.set_claim_position(study.id, "Kale-improves-anemia-", "food_related")

      raw_rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert raw_rule.kind == :unmatched
      assert {:ok, rec} = ClaimRules.verify_suggestion(condition.id, raw_rule, %{})
      assert rec.raw_food_term == "Kale"

      # Later, "Kale" is curated as a species. The re-derived suggestion is now a
      # species match, and it still reads as accepted (lines up with the raw row).
      {:ok, species} = Food.create_foundemental_species(%{name: "Kale"})

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert rule.kind == :species
      assert rule.species_id == species.id
      assert rule.already_recommended? == true
      assert rule.verified_as == "encourage"

      # Recall sweeps the stale free-text row.
      assert {:ok, 1} = ClaimRules.recall_suggestion(condition.id, rule)
      [rule2] = ClaimRules.rules_for_condition(condition.id)
      assert rule2.verified_as == nil
    end

    test "matches a food species by its scientific name" do
      {:ok, species} = Food.create_foundemental_species(%{name: "Turmeric", scientific_name: "Curcuma longa"})

      {condition, study} =
        seed(%{name: "Inflammation #{System.unique_integer([:positive])}"}, 885_002, [
          claim("Curcuma longa", "reduces", "inflammation")
        ])

      {:ok, _} =
        Literature.set_claim_position(study.id, "Curcuma longa-reduces-inflammation-", "food_related")

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert rule.kind == :species
      assert rule.species_id == species.id
    end

    test "matches a public meal blueprint by name and surfaces it via blueprints_for_condition" do
      user = user_fixture()

      {:ok, blueprint} =
        user.id
        |> MealBlueprints.default_blueprint_attrs("Mediterranean Week")
        |> Map.put(:visibility, "public")
        |> MealBlueprints.create_blueprint()

      {condition, study} =
        seed(%{name: "Heart Health #{System.unique_integer([:positive])}"}, 885_003, [
          claim("Mediterranean Week", "improves", "heart health")
        ])

      {:ok, _} =
        Literature.set_claim_position(
          study.id,
          "Mediterranean Week-improves-heart health-",
          "food_related"
        )

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert rule.kind == :blueprint
      assert rule.blueprint_id == blueprint.id

      assert {:ok, rec} = ClaimRules.verify_suggestion(condition.id, rule, %{})
      assert rec.blueprint_id == blueprint.id

      assert [row] = Health.blueprints_for_condition(condition.id)
      assert row.blueprint.id == blueprint.id

      assert {:ok, 1} = ClaimRules.recall_suggestion(condition.id, rule)
      assert Health.blueprints_for_condition(condition.id) == []
    end

    test "a private blueprint is not matchable" do
      user = user_fixture()

      {:ok, _blueprint} =
        user.id
        |> MealBlueprints.default_blueprint_attrs("Secret Plan")
        |> Map.put(:visibility, "private")
        |> MealBlueprints.create_blueprint()

      {condition, study} =
        seed(%{name: "Whatever #{System.unique_integer([:positive])}"}, 885_004, [
          claim("Secret Plan", "improves", "whatever")
        ])

      {:ok, _} =
        Literature.set_claim_position(study.id, "Secret Plan-improves-whatever-", "food_related")

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      # Falls back to unmatched — a private blueprint is never surfaced publicly.
      assert rule.kind == :unmatched
    end

    test "compound match wins over a species match on the same term" do
      {:ok, compound} = Food.upsert_compound(%{name: "Quercetin", compound_type: "polyphenol"})
      {:ok, _species} = Food.create_foundemental_species(%{name: "Quercetin"})

      {condition, study} =
        seed(%{name: "Allergy #{System.unique_integer([:positive])}"}, 885_005, [
          claim("Quercetin", "reduces", "allergy")
        ])

      {:ok, _} = Literature.set_claim_position(study.id, "Quercetin-reduces-allergy-", "food_related")

      rule = ClaimRules.rules_for_condition(condition.id) |> hd()
      assert rule.kind == :compound
      assert rule.compound_id == compound.id
    end
  end

  test "negative polarity flips a beneficial predicate to avoid" do
    {:ok, _} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {condition, _study} =
      seed(%{name: "Colitis #{System.unique_integer([:positive])}"}, 880_005, [
        claim("Oxalate", "improves", "colitis", polarity: "negative")
      ])

    assert [rule] = ClaimRules.rules_for_condition(condition.id)
    assert rule.direction == "avoid"
  end
end
