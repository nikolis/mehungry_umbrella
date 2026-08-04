defmodule Mehungry.Food.CompoundMeasurementCandidatesTest do
  @moduledoc """
  Server-side persistence + review of measurement candidates. Extraction itself now
  runs in the non-deployed `mehungry_local_ai` service and posts candidates back via
  the REST API; these tests cover the domain functions that API relies on.
  """
  use Mehungry.DataCase, async: false

  import Mehungry.FoodFixtures

  alias Mehungry.{Food, Literature}
  alias Mehungry.Food.{CompoundMeasurementCandidate, CompoundMeasurement}

  setup do
    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, vitc} = Food.upsert_compound(%{name: "L-Ascorbic Acid", compound_type: "other"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    {:ok, study} =
      Literature.upsert_study(%{
        pmid: 12_345,
        title: "Vitamin C in spinach",
        retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _} =
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: spinach.id,
        search_term: "Spinacia oleracea ascorbic"
      })

    %{spinach: spinach, vitc: vitc, species: species, study: study}
  end

  describe "upsert_measurement_candidate/1" do
    test "writes a pending candidate keyed on the species", ctx do
      assert {:ok, cand} =
               Food.upsert_measurement_candidate(%{
                 foundemental_species_id: ctx.species.id,
                 compound_id: ctx.vitc.id,
                 study_id: ctx.study.id,
                 value: 260.0,
                 unit: "mg/100 g",
                 analytical_method: "HPLC",
                 score: 0.9,
                 extraction_method: "automated"
               })

      assert cand.status == "pending"
      assert [%CompoundMeasurementCandidate{}] = Repo.all(CompoundMeasurementCandidate)
    end

    test "is idempotent on the natural key", ctx do
      attrs = %{
        foundemental_species_id: ctx.species.id,
        compound_id: ctx.vitc.id,
        study_id: ctx.study.id,
        value: 260.0,
        unit: "mg/100 g",
        score: 0.5
      }

      {:ok, _} = Food.upsert_measurement_candidate(attrs)
      {:ok, _} = Food.upsert_measurement_candidate(%{attrs | score: 0.8})

      assert Repo.aggregate(CompoundMeasurementCandidate, :count) == 1
    end
  end

  describe "accept / reject candidate" do
    setup ctx do
      {:ok, cand} =
        Food.upsert_measurement_candidate(%{
          foundemental_species_id: ctx.species.id,
          compound_id: ctx.vitc.id,
          study_id: ctx.study.id,
          value: 260.0,
          unit: "mg/100 g",
          analytical_method: "HPLC",
          score: 0.9
        })

      Map.put(ctx, :candidate, cand)
    end

    test "accept records an immutable measurement against a curated ingredient", ctx do
      assert {:ok, updated} = Food.accept_measurement_candidate(ctx.candidate.id)
      assert updated.status == "accepted"
      assert updated.accepted_measurement_id

      [m] = Food.list_measurements_for_ingredient(ctx.spinach.id)
      assert %CompoundMeasurement{} = m
      assert m.compound_id == ctx.vitc.id
      assert m.value == 260.0
      assert m.study_id == ctx.study.id
    end

    test "reject leaves the queue and writes no measurement", ctx do
      assert {:ok, updated} = Food.reject_measurement_candidate(ctx.candidate.id)
      assert updated.status == "rejected"
      assert Food.list_measurements_for_ingredient(ctx.spinach.id) == []
    end
  end
end
