defmodule Mehungry.ObanWorkers.CompoundCandidateDerivationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.CandidateDerivationRuns
  alias Mehungry.Food.CandidateDerivationRun, as: Run
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Literature
  alias Mehungry.ObanWorkers.CompoundCandidateDerivationWorker, as: Worker
  alias Mehungry.Repo

  # A spinach ingredient curated onto a Spinach species — evidence linked to the
  # ingredient rolls up to the species for derivation.
  defp spinach_species do
    spinach = ingredient_fixture(%{name: "spinach"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")
    {species, spinach}
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

  test "derives a batch, auto-promotes strong evidence, tracks progress, chains next batch" do
    {species, spinach} = spinach_species()
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    for _ <- 1..5, do: cooccur(spinach, oxalate)

    run = CandidateDerivationRuns.start_run()
    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    # Strong (5-study) species candidate auto-promoted → curated species fact written.
    assert [rel] = SpeciesCompounds.list_species_relationships(species.id)
    assert rel.compound_id == oxalate.id
    assert rel.source == "literature"

    reloaded = Repo.get!(Run, run.id)
    assert reloaded.status == "processing"
    assert reloaded.promoted_count == 1
    assert_enqueued(worker: Worker, args: %{"run_id" => run.id, "offset" => 100})
  end

  test "completes the run and stops chaining once the offset runs past the evidence pairs" do
    run = CandidateDerivationRuns.start_run()

    # No evidence pairs at all → first tick derives nothing → completed.
    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.get!(Run, run.id).status == "completed"
    refute_enqueued(worker: Worker)
  end

  test "a later tick past the end completes without re-promoting" do
    {species, spinach} = spinach_species()
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    for _ <- 1..5, do: cooccur(spinach, oxalate)

    run = CandidateDerivationRuns.start_run()
    # First tick processes the single pair; second tick (offset 100) is past the end.
    assert :ok = perform_job(Worker, %{"run_id" => run.id})
    assert :ok = perform_job(Worker, %{"run_id" => run.id, "offset" => 100})

    completed = Repo.get!(Run, run.id)
    assert completed.status == "completed"
    # Exactly one promotion happened, on the first tick.
    assert completed.promoted_count == 1
    assert length(SpeciesCompounds.list_species_relationships(species.id)) == 1
  end
end
