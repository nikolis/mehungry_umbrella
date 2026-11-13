defmodule Mehungry.FactMining.SpeciesFactMiningWorkerTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.Food
  alias Mehungry.FactMining.SpeciesFactMiningRun
  alias Mehungry.FactMining.SpeciesFactMiningRuns, as: Runs
  alias Mehungry.ObanWorkers.SpeciesFactMiningWorker
  alias Mehungry.Repo

  setup do
    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Acerola",
        "scientific_name" => "Malpighia emarginata"
      })

    on_exit(fn ->
      Application.delete_env(:mehungry, :fact_miner_stub_sheet)
      Application.delete_env(:mehungry, :fact_miner_stub_reachable)
    end)

    %{species: species}
  end

  defp one_fact_sheet do
    %{
      "query" => "q",
      "scope_kind" => "entity",
      "counts" => %{},
      "facts" => [
        %{
          "label" => "verified",
          "certainty" => "high",
          "reason" => "",
          "assessment" => nil,
          "conflicting_pmid" => nil,
          "fact" => %{
            "fact_id" => "fx_1",
            "text" => "A fact.",
            "claim_type" => "other",
            "pmid" => "1",
            "quote" => "q",
            "char_span" => [0, 1],
            "study_design" => "rct",
            "source" => "pubmed_abstract",
            "license" => "commercial_ok",
            "license_raw" => "CC0"
          }
        }
      ],
      "trace" => []
    }
  end

  describe "mine_all_species/0" do
    test "fans out one tracking row + one job per species", %{species: species} do
      Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)

      assert {:ok, batch_id} = Runs.mine_all_species()

      rows = Runs.list_batch_rows(batch_id)
      assert [%{foundemental_species_id: sid, status: "pending"}] = rows
      assert sid == species.id

      assert [job] = all_enqueued(worker: SpeciesFactMiningWorker)
      assert job.args["species_id"] == species.id
      assert job.args["batch_id"] == batch_id
      assert job.args["tracking_id"]
    end

    test "aborts without enqueuing when the miner is unreachable" do
      Application.put_env(:mehungry, :fact_miner_stub_reachable, {:error, :down})

      assert {:error, {:unreachable, :down}} = Runs.mine_all_species()
      assert all_enqueued(worker: SpeciesFactMiningWorker) == []
      assert Repo.aggregate(SpeciesFactMiningRun, :count, :id) == 0
    end
  end

  describe "perform/1" do
    test "marks the row completed with fact counts on success", %{species: species} do
      Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)
      Application.put_env(:mehungry, :fact_miner_stub_sheet, one_fact_sheet())
      {:ok, batch_id} = Runs.mine_all_species()
      [row] = Runs.list_batch_rows(batch_id)

      assert :ok =
               perform_job(SpeciesFactMiningWorker, %{
                 "tracking_id" => row.id,
                 "species_id" => species.id,
                 "batch_id" => batch_id
               })

      updated = Repo.get!(SpeciesFactMiningRun, row.id)
      assert updated.status == "completed"
      assert updated.facts_total == 1
      assert updated.verified_count == 1
    end

    test "retries on a transient error, then marks failed on the final attempt", %{
      species: species
    } do
      Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)
      Application.put_env(:mehungry, :fact_miner_stub_sheet, {:error, :boom})
      {:ok, batch_id} = Runs.mine_all_species()
      [row] = Runs.list_batch_rows(batch_id)

      args = %{"tracking_id" => row.id, "species_id" => species.id, "batch_id" => batch_id}

      # Non-final attempt → returns the error so Oban retries.
      assert {:error, :boom} = perform_job(SpeciesFactMiningWorker, args, attempt: 1)

      # Final attempt → records failed so the batch can finalize.
      assert :ok = perform_job(SpeciesFactMiningWorker, args, attempt: 3)
      assert Repo.get!(SpeciesFactMiningRun, row.id).status == "failed"
    end

    test "snoozes (does not fail) when the miner is rate-limited (429)", %{species: species} do
      Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)
      Application.put_env(:mehungry, :fact_miner_stub_sheet, {:error, {:rate_limited, 42}})
      {:ok, batch_id} = Runs.mine_all_species()
      [row] = Runs.list_batch_rows(batch_id)

      args = %{"tracking_id" => row.id, "species_id" => species.id, "batch_id" => batch_id}

      # Even on the final attempt a 429 snoozes per Retry-After instead of failing.
      assert {:snooze, 42} = perform_job(SpeciesFactMiningWorker, args, attempt: 3)
      refute Repo.get!(SpeciesFactMiningRun, row.id).status == "failed"
    end
  end

  describe "counts_for_batch/1" do
    test "aggregates status + facts over the batch", %{species: species} do
      Application.put_env(:mehungry, :fact_miner_stub_reachable, :ok)
      Application.put_env(:mehungry, :fact_miner_stub_sheet, one_fact_sheet())
      {:ok, batch_id} = Runs.mine_all_species()
      [row] = Runs.list_batch_rows(batch_id)

      assert Runs.counts_for_batch(batch_id).pending == 1

      Runs.mark_completed(row.id, %{total: 3, verified: 2, contradicted: 1})
      counts = Runs.counts_for_batch(batch_id)
      assert counts.completed == 1
      assert counts.facts_total == 3
      refute Runs.batch_in_flight?(batch_id)

      _ = species
    end
  end
end
