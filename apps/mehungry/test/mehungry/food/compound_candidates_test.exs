defmodule Mehungry.Food.CompoundCandidatesTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.CompoundCandidates
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Food.SpeciesCompoundRelationship
  alias Mehungry.Literature

  setup do
    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

    {:ok, species} =
      Food.create_foundemental_species(%{"name" => "Spinach", "scientific_name" => "Spinacia oleracea"})

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    %{spinach: spinach, oxalate: oxalate, species: species}
  end

  # One study that mentions `compound` (a resolved chemical) in a paper linked to
  # `ingredient` — one unit of co-occurrence evidence that rolls up to the species.
  defp cooccur(ingredient, compound, term \\ "spinach oxalate") do
    pmid = System.unique_integer([:positive])
    {:ok, study} = Literature.upsert_study(%{pmid: pmid, title: "s#{pmid}"})

    {:ok, _} =
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: ingredient.id,
        search_term: term
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

    study
  end

  defp measurement(ingredient, compound, value) do
    pmid = System.unique_integer([:positive])

    {:ok, study} =
      Literature.upsert_study(%{pmid: pmid, title: "m#{pmid}", publication_date: "2024"})

    {:ok, _} =
      Food.create_measurement(%{
        ingredient_id: ingredient.id,
        compound_id: compound.id,
        study_id: study.id,
        value: value,
        unit: "mg/100g",
        preparation_method: "Raw",
        analytical_method: "HPLC",
        sample_size: 15,
        extraction_method: "automated"
      })
  end

  defp species_rels(species_id), do: SpeciesCompounds.list_species_relationships(species_id)

  describe "species co-occurrence evidence" do
    test "counts distinct studies mentioning the compound in the species' papers", ctx do
      for _ <- 1..3, do: cooccur(ctx.spinach, ctx.oxalate)
      assert Literature.species_cooccurrence_study_count(ctx.species.id, ctx.oxalate.id) == 3
    end

    test "a mention in a study linked to no ingredient of the species does not count", ctx do
      {:ok, study} = Literature.upsert_study(%{pmid: 999_001, title: "orphan"})

      {:ok, _} =
        Literature.upsert_entity_mention(%{
          study_id: study.id,
          entity_type: "chemical",
          normalized_identifier: "mesh:Dorphan",
          text_span: "oxalic acid",
          offset: 1,
          compound_id: ctx.oxalate.id
        })

      assert Literature.species_cooccurrence_study_count(ctx.species.id, ctx.oxalate.id) == 0
    end
  end

  describe "score_candidate/2 — noisy-OR blend" do
    test "literature-only saturates at 5 studies → strong", ctx do
      for _ <- 1..5, do: cooccur(ctx.spinach, ctx.oxalate)
      scored = CompoundCandidates.score_candidate(ctx.species.id, ctx.oxalate.id)

      assert scored.evidence_score == 1.0
      assert scored.evidence_level == "strong"
      assert scored.study_count == 5
      assert scored.sources == ["pubtator"]
    end

    test "two literature studies → 0.4 → limited", ctx do
      for _ <- 1..2, do: cooccur(ctx.spinach, ctx.oxalate)
      scored = CompoundCandidates.score_candidate(ctx.species.id, ctx.oxalate.id)

      assert scored.evidence_score == 0.4
      assert scored.evidence_level == "limited"
    end

    test "measurement-only (across the species' ingredients) scores positive", ctx do
      for v <- [740.0, 750.0, 760.0], do: measurement(ctx.spinach, ctx.oxalate, v)
      scored = CompoundCandidates.score_candidate(ctx.species.id, ctx.oxalate.id)

      assert scored.study_count == 0
      assert scored.measurement_study_count == 3
      assert "measurement" in scored.sources
      assert scored.evidence_score > 0.0
    end

    test "both sources compound above either alone (noisy-OR)", ctx do
      for _ <- 1..2, do: cooccur(ctx.spinach, ctx.oxalate)
      for v <- [740.0, 750.0, 760.0], do: measurement(ctx.spinach, ctx.oxalate, v)

      scored = CompoundCandidates.score_candidate(ctx.species.id, ctx.oxalate.id)
      assert scored.evidence_score > 0.4
      assert Enum.sort(scored.sources) == ["measurement", "pubtator"]
    end
  end

  describe "derive_candidate/3 — auto-promotion + study provenance" do
    test "score ≥ threshold auto-promotes and writes a species fact", ctx do
      for _ <- 1..5, do: cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: candidate, promoted: true}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      assert candidate.status == "promoted"
      assert candidate.promoted_relationship_id

      [rel] = species_rels(ctx.species.id)
      assert %SpeciesCompoundRelationship{} = rel
      assert rel.compound_id == ctx.oxalate.id
      assert rel.source == "literature"
      assert rel.relationship_type == "contains"
      assert rel.confidence == 1.0
    end

    test "records the reference studies the suggestion was extracted from", ctx do
      s1 = cooccur(ctx.spinach, ctx.oxalate)
      s2 = cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: candidate}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      pmids = CompoundCandidates.list_candidate_studies(candidate.id) |> Enum.map(& &1.pmid)
      assert Enum.sort(pmids) == Enum.sort([s1.pmid, s2.pmid])
    end

    test "score below threshold stays pending and writes no fact", ctx do
      cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: candidate, promoted: false}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      assert candidate.status == "pending"
      assert species_rels(ctx.species.id) == []
    end

    test "re-derivation refreshes evidence but never un-reviews a decided candidate", ctx do
      cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: candidate}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      {:ok, rejected} = CompoundCandidates.reject_candidate(candidate)
      assert rejected.status == "rejected"

      for _ <- 1..5, do: cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: re_derived, promoted: promoted}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      assert re_derived.status == "rejected"
      assert promoted == false
      assert re_derived.study_count == 6
      assert species_rels(ctx.species.id) == []
    end
  end

  describe "manual review" do
    test "promote_candidate writes the fact, is idempotent, and marks promoted", ctx do
      cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: candidate}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      assert candidate.status == "pending"

      {:ok, promoted} = CompoundCandidates.promote_candidate(candidate)
      assert promoted.status == "promoted"
      assert [_rel] = species_rels(ctx.species.id)

      {:ok, _} = CompoundCandidates.promote_candidate(promoted)
      assert length(species_rels(ctx.species.id)) == 1
    end

    test "reject_candidate leaves the queue and writes no fact", ctx do
      cooccur(ctx.spinach, ctx.oxalate)

      {:ok, %{candidate: candidate}} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id)

      {:ok, rejected} = CompoundCandidates.reject_candidate(candidate)
      assert rejected.status == "rejected"
      assert CompoundCandidates.list_pending_candidates() == []
      assert species_rels(ctx.species.id) == []
    end

    test "import_manual_candidate creates a manual-source pending candidate", ctx do
      {:ok, candidate} =
        CompoundCandidates.import_manual_candidate(ctx.species.id, ctx.oxalate.id, %{
          notes: "expert assertion"
        })

      assert candidate.status == "pending"
      assert candidate.sources == ["manual"]

      {:ok, promoted} = CompoundCandidates.promote_candidate(candidate)
      [rel] = species_rels(ctx.species.id)
      assert promoted.status == "promoted"
      assert rel.source == "manual"
    end

    test "list_pending_candidates orders by evidence strongest-first", ctx do
      {:ok, weak} = Food.upsert_compound(%{name: "Weakly", compound_type: "other"})
      for _ <- 1..5, do: cooccur(ctx.spinach, ctx.oxalate)
      cooccur(ctx.spinach, weak)

      {:ok, _} =
        CompoundCandidates.derive_candidate(ctx.species.id, ctx.oxalate.id, threshold: 2.0)

      {:ok, _} = CompoundCandidates.derive_candidate(ctx.species.id, weak.id, threshold: 2.0)

      [first, second] = CompoundCandidates.list_pending_candidates()
      assert first.compound_id == ctx.oxalate.id
      assert first.evidence_score >= second.evidence_score
    end
  end

  describe "feedback loop query" do
    test "list_positive_compounds_for_species excludes 'absent' facts", ctx do
      {:ok, gone} = Food.upsert_compound(%{name: "Gone", compound_type: "other"})

      {:ok, _} =
        Food.upsert_species_relationship(%{
          foundemental_species_id: ctx.species.id,
          compound_id: ctx.oxalate.id,
          relationship_type: "contains",
          source: "literature"
        })

      {:ok, _} =
        Food.upsert_species_relationship(%{
          foundemental_species_id: ctx.species.id,
          compound_id: gone.id,
          relationship_type: "absent",
          source: "literature"
        })

      names = Food.list_positive_compounds_for_species(ctx.species.id) |> Enum.map(& &1.name)
      assert names == ["Oxalate"]
    end
  end

  describe "non-dietary blocklist" do
    test "excludes blocklisted compounds from evidence pairs", %{spinach: spinach, oxalate: oxalate, species: species} do
      {:ok, dpph} = Food.upsert_compound(%{name: "DPPH", compound_type: "other"})
      cooccur(spinach, oxalate)
      cooccur(spinach, dpph)

      pairs = CompoundCandidates.evidence_pairs()
      assert {species.id, oxalate.id} in pairs
      refute {species.id, dpph.id} in pairs
    end

    test "purge_blocklisted deletes species facts + candidates for blocklisted compounds", %{
      species: species
    } do
      {:ok, dpph} = Food.upsert_compound(%{name: "DPPH", compound_type: "other"})
      {:ok, cand} = CompoundCandidates.import_manual_candidate(species.id, dpph.id, %{})
      {:ok, _} = CompoundCandidates.promote_candidate(cand.id)

      assert Repo.aggregate(from(r in SpeciesCompoundRelationship, where: r.compound_id == ^dpph.id), :count) == 1

      assert {rels, cands} = CompoundCandidates.purge_blocklisted()
      assert rels >= 1 and cands >= 1
      assert Repo.aggregate(from(r in SpeciesCompoundRelationship, where: r.compound_id == ^dpph.id), :count) == 0
    end
  end

  describe "unpromote_relationship/1" do
    test "deletes the fact and rejects its candidate", %{spinach: spinach, oxalate: oxalate, species: species} do
      cooccur(spinach, oxalate)

      {:ok, %{candidate: cand, promoted: true}} =
        CompoundCandidates.derive_candidate(species.id, oxalate.id, threshold: 0.0)

      rel_id = cand.promoted_relationship_id
      assert Repo.get(SpeciesCompoundRelationship, rel_id)

      {:ok, _} = CompoundCandidates.unpromote_relationship(rel_id)

      refute Repo.get(SpeciesCompoundRelationship, rel_id)
      assert CompoundCandidates.get_candidate!(cand.id).status == "rejected"
    end
  end
end
