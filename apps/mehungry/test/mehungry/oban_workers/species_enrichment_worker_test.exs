defmodule Mehungry.ObanWorkers.SpeciesEnrichmentWorkerTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesFact
  alias Mehungry.Food.SpeciesEnrichmentRuns, as: Runs
  alias Mehungry.ObanWorkers.SpeciesEnrichmentWorker
  alias Mehungry.Repo

  # Minimal client stubs over the :wikidata_client / :faostat_client seams.
  defmodule WikidataStub do
    def fetch(_name, _scientific_name) do
      {:ok, %{qid: "Q89", origin_region: "Central Asia", descriptions: %{"en" => "a fruit"}}}
    end
  end

  defmodule FaostatStub do
    def load_rows do
      {:ok, [%{item_code: "515", area: "China", value_tonnes: 100.0, year: 2022, item: "Apples"}]}
    end
  end

  setup do
    Application.put_env(:mehungry, :wikidata_client, WikidataStub)
    Application.put_env(:mehungry, :faostat_client, FaostatStub)

    on_exit(fn ->
      Application.delete_env(:mehungry, :wikidata_client)
      Application.delete_env(:mehungry, :faostat_client)
    end)

    :ok
  end

  defp species_with_faostat_code do
    {:ok, sp} =
      Food.create_foundemental_species(%{
        "name" => "Apple",
        "scientific_name" => "Malus domestica"
      })

    sp |> Ecto.Changeset.change(%{faostat_item_code: "515"}) |> Repo.update!()
  end

  test "enriches a species — FAOSTAT auto-promoted, Wikidata pending, run completed with counts" do
    species_with_faostat_code()
    {:ok, batch_id} = Runs.enrich_all_species()
    [job] = all_enqueued(worker: SpeciesEnrichmentWorker)

    assert :ok = perform_job(SpeciesEnrichmentWorker, job.args)

    [run] = Runs.list_batch_rows(batch_id)
    assert run.status == "completed"
    # origin_region + description(en)
    assert run.wikidata_count == 2
    assert run.faostat_count == 1

    facts = Repo.all(SpeciesFact)

    faostat = Enum.find(facts, &(&1.fact_key == "top_producers"))
    assert faostat.status == "promoted"
    assert faostat.value_text =~ "China"

    wikidata = Enum.filter(facts, &(&1.fact_key in ["origin_region", "description"]))
    assert length(wikidata) == 2
    assert Enum.all?(wikidata, &(&1.status == "pending"))
  end
end
