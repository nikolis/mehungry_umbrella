defmodule Mehungry.FoodData.Usda.SeedFilesTest do
  use Mehungry.DataCase

  alias Mehungry.FoodData.Usda.{SeedFile, SeedFiles}
  alias Mehungry.Repo

  describe "upsert_pending/2" do
    test "inserts a new pending row and broadcasts it" do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, SeedFiles.topic("b"))

      seed_file = SeedFiles.upsert_pending("b", "k.json")

      assert %SeedFile{status: "pending", bucket: "b", key: "k.json"} = seed_file
      assert_received {:seed_file, %SeedFile{key: "k.json", status: "pending"}}
    end

    test "resets an existing completed/failed row back to pending" do
      seed_file = SeedFiles.upsert_pending("b", "k.json")
      SeedFiles.mark_completed(seed_file.id, 42)

      reset = SeedFiles.upsert_pending("b", "k.json")

      assert reset.id == seed_file.id
      assert reset.status == "pending"
      assert is_nil(reset.ingredient_count)
      assert is_nil(reset.completed_at)
      assert is_nil(reset.error)
    end
  end

  describe "mark_* transitions broadcast the row" do
    test "mark_completed and mark_failed" do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, SeedFiles.topic("b"))
      seed_file = SeedFiles.upsert_pending("b", "k.json")
      assert_received {:seed_file, %SeedFile{status: "pending"}}

      # mark_processing deliberately does not broadcast — the UI doesn't need the
      # pending→processing tick, only the terminal completed/failed transitions.
      SeedFiles.mark_processing(seed_file.id)
      refute_received {:seed_file, %SeedFile{status: "processing"}}

      SeedFiles.mark_completed(seed_file.id, 7)
      assert_received {:seed_file, %SeedFile{status: "completed", ingredient_count: 7}}

      other = SeedFiles.upsert_pending("b", "k2.json")
      SeedFiles.mark_failed(other.id, {:invalid_json, :unexpected})
      assert_received {:seed_file, %SeedFile{status: "failed", error: error}}
      assert error =~ "invalid_json"
    end
  end

  describe "list_by_bucket/2" do
    test "keys rows by object key, scoped by bucket and prefix" do
      SeedFiles.upsert_pending("b", "foods/a.json")
      SeedFiles.upsert_pending("b", "foods/b.json")
      SeedFiles.upsert_pending("b", "other/c.json")
      SeedFiles.upsert_pending("other-bucket", "foods/a.json")

      all = SeedFiles.list_by_bucket("b")
      assert Map.keys(all) |> Enum.sort() == ["foods/a.json", "foods/b.json", "other/c.json"]

      scoped = SeedFiles.list_by_bucket("b", "foods/")
      assert Map.keys(scoped) |> Enum.sort() == ["foods/a.json", "foods/b.json"]
    end
  end

  describe "pending_or_failed/2" do
    test "excludes completed keys, keeps failed/pending/never-seen ones" do
      done = SeedFiles.upsert_pending("b", "done.json")
      SeedFiles.mark_completed(done.id, 1)

      failed = SeedFiles.upsert_pending("b", "failed.json")
      SeedFiles.mark_failed(failed.id, :boom)

      SeedFiles.upsert_pending("b", "pending.json")

      keys = ["done.json", "failed.json", "pending.json", "never_seen.json"]

      assert SeedFiles.pending_or_failed("b", keys) |> Enum.sort() ==
               ["failed.json", "never_seen.json", "pending.json"]
    end
  end

  describe "reset/2" do
    test "deletes tracking rows and cancels pending import jobs for the bucket" do
      keep = SeedFiles.upsert_pending("other-bucket", "foods/a.json")
      SeedFiles.upsert_pending("b", "foods/a.json")
      {:ok, job} = Mehungry.ObanWorkers.SeedFileImportWorker.enqueue("b", "foods/b.json")

      assert SeedFiles.reset("b") == 2

      # Rows for the reset bucket are gone; other buckets are untouched.
      assert SeedFiles.list_by_bucket("b") == %{}
      assert Map.has_key?(SeedFiles.list_by_bucket("other-bucket"), "foods/a.json")
      assert Repo.get(SeedFile, keep.id)

      # The queued import job was cancelled, not left to run against a deleted row.
      assert %Oban.Job{state: "cancelled"} = Repo.get(Oban.Job, job.id)
    end

    test "prefix scope only resets matching keys" do
      SeedFiles.upsert_pending("b", "foods/a.json")
      SeedFiles.upsert_pending("b", "other/c.json")

      assert SeedFiles.reset("b", "foods/") == 1
      assert Map.keys(SeedFiles.list_by_bucket("b")) == ["other/c.json"]
    end
  end

  describe "status transitions tolerate a deleted row" do
    test "mark_* on a reset (deleted) row is a no-op returning nil" do
      seed_file = SeedFiles.upsert_pending("b", "k.json")
      SeedFiles.reset("b")

      # A job still running after reset must not crash on the missing row.
      assert SeedFiles.mark_processing(seed_file.id) == nil
      assert SeedFiles.mark_completed(seed_file.id, 5) == nil
      assert SeedFiles.mark_failed(seed_file.id, :boom) == nil
    end
  end

  test "changeset rejects invalid status" do
    changeset = SeedFile.changeset(%SeedFile{}, %{bucket: "b", key: "k", status: "bogus"})
    refute changeset.valid?
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end
end
