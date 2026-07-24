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

      SeedFiles.mark_processing(seed_file.id)
      assert_received {:seed_file, %SeedFile{status: "processing"}}

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

  test "changeset rejects invalid status" do
    changeset = SeedFile.changeset(%SeedFile{}, %{bucket: "b", key: "k", status: "bogus"})
    refute changeset.valid?
    assert %{status: ["is invalid"]} = errors_on(changeset)
  end
end
