defmodule Mehungry.Food.GlycemicIndexTest do
  use Mehungry.DataCase, async: true

  import Mehungry.FoodFixtures

  alias Mehungry.{Food, Literature}
  alias Mehungry.Food.GlycemicIndexCandidate
  alias Mehungry.Food.IngredientScientificProperty

  setup do
    study = make_study(pmid: 42_001, title: "GI of banana", doi: "10.1/banana")
    %{study: study}
  end

  # ── Extraction intake (fan-out) ──────────────────────────────────────────────

  describe "record_extracted_gi/3" do
    test "fans each finding over every linked species and cites the study", ctx do
      s1 = species_with_ingredients("Banana", 2)
      s2 = species_with_ingredients("Plantain", 1)

      finding = %{gi_value: 51.0, gi_sem: 3.0, iso_method: true, country: "Australia", year: 2019}

      assert 2 == Food.record_extracted_gi(ctx.study.id, [finding], [s1.id, s2.id])

      cands = Repo.all(GlycemicIndexCandidate)
      assert length(cands) == 2
      assert Enum.all?(cands, &(&1.status == "pending"))
      assert Enum.all?(cands, &(&1.gi_value == 51.0))
      assert Enum.all?(cands, &(&1.study_id == ctx.study.id))
      # every candidate cites the primary study (its DOI here)
      assert Enum.all?(cands, & &1.enrichment_source_id)
    end

    test "is idempotent on (study, species, value); refreshes extraction fields", ctx do
      s1 = species_with_ingredients("Banana", 1)

      assert 1 == Food.record_extracted_gi(ctx.study.id, [%{gi_value: 51.0, iso_method: false}], [s1.id])
      assert 1 == Food.record_extracted_gi(ctx.study.id, [%{gi_value: 51.0, iso_method: true}], [s1.id])

      assert [cand] = Repo.all(GlycemicIndexCandidate)
      assert cand.iso_method
    end

    test "does not auto-promote — everything waits for review", ctx do
      s1 = species_with_ingredients("Banana", 2)
      Food.record_extracted_gi(ctx.study.id, [%{gi_value: 51.0, iso_method: true}], [s1.id])

      assert Food.count_pending_glycemic_candidates() == 1
      assert Food.count_promoted_glycemic_candidates() == 0
    end
  end

  # ── Promote / reject / undo ──────────────────────────────────────────────────

  describe "promote / reject / undo" do
    test "promote fans the value onto every ingredient; undo deletes exactly those", ctx do
      species = species_with_ingredients("Mango", 2)
      Food.record_extracted_gi(ctx.study.id, [%{gi_value: 60.0, score: 0.9}], [species.id])
      [candidate] = Food.list_pending_glycemic_candidates()

      {:ok, promoted} = Food.promote_glycemic_candidate(candidate)
      assert promoted.status == "promoted"
      assert length(promoted.promoted_property_ids) == 2

      [i1, i2] = Food.list_ingredient_ids_for_species(species.id)

      for ingredient_id <- [i1, i2] do
        assert [%IngredientScientificProperty{} = p] =
                 Food.list_scientific_properties(ingredient_id)

        assert p.property_key == "glycemic_index"
        assert p.value == 60.0
        assert p.basis == "glucose=100"
        assert p.source == "external_db"
        assert p.reviewed
      end

      {:ok, undone} = Food.unpromote_glycemic_candidate(promoted)
      assert undone.status == "rejected"
      assert Food.list_scientific_properties(i1) == []
      assert Food.list_scientific_properties(i2) == []
    end

    test "promote onto a species with no ingredients returns :no_ingredients", ctx do
      {:ok, species} = Food.create_foundemental_species(%{name: "Quince"})
      Food.record_extracted_gi(ctx.study.id, [%{gi_value: 35.0}], [species.id])
      [candidate] = Food.list_pending_glycemic_candidates()

      assert {:error, :no_ingredients} = Food.promote_glycemic_candidate(candidate)
    end

    test "promote_candidate/2 overrides the fanned species before writing", ctx do
      wrong = species_with_ingredients("Apple", 1)
      pear = species_with_ingredients("Pear", 1)
      Food.record_extracted_gi(ctx.study.id, [%{gi_value: 38.0}], [wrong.id])
      [candidate] = Food.list_pending_glycemic_candidates()

      {:ok, promoted} = Food.promote_glycemic_candidate(candidate.id, pear.id)
      assert promoted.foundemental_species_id == pear.id

      [pear_ingredient] = Food.list_ingredient_ids_for_species(pear.id)
      assert [_] = Food.list_scientific_properties(pear_ingredient)
    end

    test "reject leaves the queue and writes no fact", ctx do
      species = species_with_ingredients("Rice", 1)
      Food.record_extracted_gi(ctx.study.id, [%{gi_value: 73.0}], [species.id])
      [candidate] = Food.list_pending_glycemic_candidates()

      {:ok, _} = Food.reject_glycemic_candidate(candidate)
      assert Food.count_pending_glycemic_candidates() == 0

      [ingredient_id] = Food.list_ingredient_ids_for_species(species.id)
      assert Food.list_scientific_properties(ingredient_id) == []
    end
  end

  # ── Ordering ─────────────────────────────────────────────────────────────────

  test "pending list orders ISO-method + higher score first", ctx do
    a = species_with_ingredients("A", 1)
    b = species_with_ingredients("B", 1)
    Food.record_extracted_gi(ctx.study.id, [%{gi_value: 10.0, iso_method: false, score: 0.9}], [a.id])
    Food.record_extracted_gi(ctx.study.id, [%{gi_value: 20.0, iso_method: true, score: 0.1}], [b.id])

    assert [first, _second] = Food.list_pending_glycemic_candidates()
    assert first.iso_method
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp species_with_ingredients(name, n) do
    {:ok, species} = Food.create_foundemental_species(%{name: name})

    for _ <- 1..n do
      ingredient = ingredient_fixture()
      Food.assign_foundemental_ingredient(species.id, ingredient.id, ingredient.name)
    end

    species
  end

  defp make_study(attrs) do
    {:ok, study} =
      attrs
      |> Map.new()
      |> Map.put_new(:retrieved_at, DateTime.utc_now() |> DateTime.truncate(:second))
      |> Literature.upsert_study()

    study
  end
end
