defmodule Mehungry.Food.SpeciesEnrichmentRunsTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesEnrichmentRun
  alias Mehungry.Food.SpeciesEnrichmentRuns, as: Runs
  alias Mehungry.ObanWorkers.SpeciesEnrichmentWorker
  alias Mehungry.Repo

  defp species(name) do
    {:ok, sp} = Food.create_foundemental_species(%{"name" => name})
    sp
  end

  describe "enrich_all_species/0" do
    test "opens one pending tracking row + one job per species" do
      species("Apple")
      species("Pear")

      assert {:ok, batch_id} = Runs.enrich_all_species()

      rows = Runs.list_batch_rows(batch_id)
      assert length(rows) == 2
      assert Enum.all?(rows, &(&1.status == "pending"))

      assert_enqueued(worker: SpeciesEnrichmentWorker)
      jobs = all_enqueued(worker: SpeciesEnrichmentWorker)
      assert length(jobs) == 2
      assert Enum.all?(jobs, &(&1.args["batch_id"] == batch_id))

      counts = Runs.counts_for_batch(batch_id)
      assert counts.pending == 2
      assert counts.total == 2
      assert counts.facts_total == 0
    end

    test "errors when there are no species" do
      assert {:error, :no_species} = Runs.enrich_all_species()
    end
  end

  describe "lifecycle + counts" do
    test "processing -> completed records per-source counts" do
      species("Apple")
      {:ok, batch_id} = Runs.enrich_all_species()
      [row] = Runs.list_batch_rows(batch_id)

      assert %SpeciesEnrichmentRun{status: "processing"} = Runs.mark_processing(row.id)
      Runs.mark_completed(row.id, %{wikidata: 3, faostat: 1})

      updated = Repo.get(SpeciesEnrichmentRun, row.id)
      assert updated.status == "completed"
      assert updated.wikidata_count == 3
      assert updated.faostat_count == 1

      counts = Runs.counts_for_batch(batch_id)
      assert counts.completed == 1
      assert counts.facts_total == 4
      refute Runs.batch_in_flight?(batch_id)
    end

    test "mark_failed records the error and finalizes the row" do
      species("Apple")
      {:ok, batch_id} = Runs.enrich_all_species()
      [row] = Runs.list_batch_rows(batch_id)

      Runs.mark_failed(row.id, "boom")

      updated = Repo.get(SpeciesEnrichmentRun, row.id)
      assert updated.status == "failed"
      assert updated.error =~ "boom"
    end
  end

  describe "cancel_batch/1" do
    test "marks unfinished rows failed and leaves the batch not in-flight" do
      species("Apple")
      {:ok, batch_id} = Runs.enrich_all_species()

      assert :cancelled = Runs.cancel_batch(batch_id)
      refute Runs.batch_in_flight?(batch_id)

      [row] = Runs.list_batch_rows(batch_id)
      assert row.status == "failed"
      assert row.error == "cancelled by admin"
    end
  end
end
