defmodule MehungrySeasonality.FetchTest do
  use MehungrySeasonality.Case, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias MehungrySeasonality.{Fetcher, Runs}
  alias MehungrySeasonality.Workers.FetchWorker

  defp cell(country, species_id, month) do
    row = Enum.find(MehungrySeasonality.grid(country), &(&1.species.id == species_id))
    row.months[month]
  end

  describe "Fetcher.fetch_species/3" do
    test "stores both signals and derives independent local + import statuses" do
      peach = species_fixture("Peach")
      map_species(peach, agridata: "Peaches", comext: "080930")

      assert %{local: 12, import: 12} = Fetcher.fetch_species(peach, "GR", year: 2026)

      statuses = MehungrySeasonality.for_species(peach, "GR")
      assert statuses[7].local == "in_season"
      assert statuses[1].local == "none"
      assert statuses[9].imported == "major"
      assert statuses[9].top_origins == [%{"country" => "TR", "share" => 1.0}]
      assert statuses[1].imported == "none"
      assert statuses[7].imported == "none"

      assert %{local: %{weeks_quoted: 4}, import: %{tonnes_avg: july_tonnes}} =
               cell("GR", peach, 7)

      assert july_tonnes == 0.0
      assert %{import: %{tonnes_avg: 500.0}} = cell("GR", peach, 9)
    end

    test "a source without a mapping reads unknown" do
      peach = species_fixture("Peach")
      map_species(peach, comext: "080930")

      assert %{local: 0, import: 12} = Fetcher.fetch_species(peach, "GR", year: 2026)

      statuses = MehungrySeasonality.for_species(peach, "GR")
      assert statuses[7].local == "unknown"
      assert statuses[9].imported == "major"
    end

    test "countries are kept apart" do
      peach = species_fixture("Peach")
      map_species(peach, agridata: "Peaches")
      Fetcher.fetch_species(peach, "GR", year: 2026)

      assert MehungrySeasonality.for_species(peach, "IT") == %{}
    end

    test "a failing API raises so the job retries" do
      peach = species_fixture("Peach")
      map_species(peach, agridata: "Peaches")

      Application.put_env(
        :mehungry_seasonality,
        :agridata_client,
        MehungrySeasonality.TestStubs.Failing
      )

      assert_raise RuntimeError, ~r/agri-food portal fetch failed/, fn ->
        Fetcher.fetch_species(peach, "GR", year: 2026)
      end
    end
  end

  describe "overrides" do
    setup do
      peach = species_fixture("Peach")
      map_species(peach, agridata: "Peaches", comext: "080930")
      Fetcher.fetch_species(peach, "GR", year: 2026)
      %{peach: peach, key: %{species_id: peach, country: "GR", month: 1}}
    end

    test "a curated value survives a re-fetch; the other fact stays derived", ctx do
      assert {:ok, status} =
               MehungrySeasonality.override_status(ctx.key, %{
                 "local" => "stored",
                 "imported" => "",
                 "note" => "cold storage until February"
               })

      assert status.local == "stored"
      assert status.local_curated
      refute status.imported_curated
      assert status.imported == "none"

      Fetcher.fetch_species(ctx.peach, "GR", year: 2026)

      january = MehungrySeasonality.for_species(ctx.peach, "GR")[1]
      assert january.local == "stored"
      assert january.note == "cold storage until February"
    end

    test "clearing an override returns the month to its derived value", ctx do
      {:ok, _} = MehungrySeasonality.override_status(ctx.key, %{"local" => "greenhouse"})
      assert :ok = MehungrySeasonality.clear_override(ctx.key)

      january = MehungrySeasonality.for_species(ctx.peach, "GR")[1]
      assert january.local == "none"
      refute january.local_curated
      assert january.note == nil
    end

    test "an invalid value is rejected", ctx do
      assert {:error, %Ecto.Changeset{}} =
               MehungrySeasonality.override_status(ctx.key, %{"local" => "tasty"})
    end
  end

  describe "fetch runs" do
    test "fans out one job per mapped species and tracks it to completion" do
      peach = species_fixture("Peach")
      _unmapped = species_fixture("Quinoa")
      map_species(peach, agridata: "Peaches", comext: "080930")
      Phoenix.PubSub.subscribe(Mehungry.PubSub, MehungrySeasonality.runs_topic())

      assert {:ok, batch_id} = MehungrySeasonality.fetch_country("GR")
      assert MehungrySeasonality.latest_batch_id("GR") == batch_id
      assert MehungrySeasonality.batch_in_flight?(batch_id)

      assert [%{status: "pending", species: %{name: "Peach"}}] =
               MehungrySeasonality.list_batch_rows(batch_id)

      assert_enqueued(worker: FetchWorker, queue: :seasonality, args: %{"species_id" => peach})
      assert {:error, :already_running} = MehungrySeasonality.fetch_country("GR")

      assert %{success: 1} = Oban.drain_queue(queue: :seasonality)

      assert_receive {:seasonality_processing, ^batch_id, ^peach}
      assert_receive {:seasonality_run, %{status: "completed", species: %{name: "Peach"}}}

      assert %{completed: 1, total: 1, pending: 0} =
               MehungrySeasonality.counts_for_batch(batch_id)

      assert [%{local_count: 12, import_count: 12}] =
               MehungrySeasonality.list_batch_rows(batch_id)

      refute MehungrySeasonality.batch_in_flight?(batch_id)
    end

    test "refuses an unsupported country and an empty crosswalk" do
      assert {:error, :unsupported_country} = MehungrySeasonality.fetch_country("US")
      assert {:error, :no_mappings} = MehungrySeasonality.fetch_country("GR")
    end

    test "records the species as failed once retries are exhausted" do
      peach = species_fixture("Peach")
      map_species(peach, agridata: "Peaches")

      Application.put_env(
        :mehungry_seasonality,
        :agridata_client,
        MehungrySeasonality.TestStubs.Failing
      )

      {:ok, batch_id} = MehungrySeasonality.fetch_country("GR")
      [run] = MehungrySeasonality.list_batch_rows(batch_id)

      args = %{
        "tracking_id" => run.id,
        "species_id" => peach,
        "country" => "GR",
        "batch_id" => batch_id
      }

      assert_raise RuntimeError, fn ->
        FetchWorker.perform(%Oban.Job{args: args, attempt: 1, max_attempts: 3})
      end

      assert :ok = FetchWorker.perform(%Oban.Job{args: args, attempt: 3, max_attempts: 3})

      assert [%{status: "failed", error: error}] = MehungrySeasonality.list_batch_rows(batch_id)
      assert error =~ "agri-food portal fetch failed"
    end

    test "cancel marks unfinished rows failed and frees the country" do
      peach = species_fixture("Peach")
      map_species(peach, agridata: "Peaches")
      {:ok, batch_id} = MehungrySeasonality.fetch_country("GR")

      assert :cancelled = MehungrySeasonality.cancel_batch(batch_id)
      assert [%{status: "failed", error: "cancelled by admin"}] = Runs.list_batch_rows(batch_id)
      assert {:ok, _new_batch} = MehungrySeasonality.fetch_country("GR")
    end
  end
end
