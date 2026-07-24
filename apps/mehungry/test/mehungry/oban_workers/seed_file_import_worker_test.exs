defmodule Mehungry.ObanWorkers.SeedFileImportWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.FoodData.Usda.{SeedFile, SeedFiles}
  alias Mehungry.ObanWorkers.SeedFileImportWorker
  alias Mehungry.Repo

  # The `:seed_file_fetcher` is stubbed to `SeedFileFetcherStub` in config/test.exs;
  # each test drives its response through `:seed_file_fetcher_stub`.
  defp stub_fetcher(fun) do
    Application.put_env(:mehungry, :seed_file_fetcher_stub, fun)
    on_exit(fn -> Application.delete_env(:mehungry, :seed_file_fetcher_stub) end)
  end

  defp valid_body(name) do
    Poison.encode!([
      %{
        "description" => name,
        "foodClass" => "FinalFood",
        "publicationDate" => "4/1/2019",
        "foodCategory" => %{"description" => "Vegetables"},
        "nutrientConversionFactors" => [],
        "foodNutrients" => [],
        "foodPortions" => []
      }
    ])
  end

  test "marks the seed file completed with the inserted count on success" do
    name = "Seed Worker Food #{System.unique_integer([:positive])}"
    stub_fetcher(fn _bucket, _key -> {:ok, valid_body(name)} end)

    seed_file = SeedFiles.upsert_pending("my-bucket", "foods/a.json")

    assert :ok =
             perform_job(SeedFileImportWorker, %{
               "seed_file_id" => seed_file.id,
               "bucket" => "my-bucket",
               "key" => "foods/a.json"
             })

    reloaded = Repo.get!(SeedFile, seed_file.id)
    assert reloaded.status == "completed"
    assert reloaded.ingredient_count == 1
    assert reloaded.completed_at
    assert is_nil(reloaded.error)
  end

  test "marks the seed file failed and returns an error when parsing fails" do
    stub_fetcher(fn _bucket, _key -> {:ok, "not valid json"} end)

    seed_file = SeedFiles.upsert_pending("my-bucket", "foods/bad.json")

    assert {:error, _reason} =
             perform_job(SeedFileImportWorker, %{
               "seed_file_id" => seed_file.id,
               "bucket" => "my-bucket",
               "key" => "foods/bad.json"
             })

    reloaded = Repo.get!(SeedFile, seed_file.id)
    assert reloaded.status == "failed"
    assert reloaded.error =~ "invalid_json"
  end

  test "marks the seed file failed when the fetch itself fails" do
    stub_fetcher(fn _bucket, _key -> {:error, :timeout} end)

    seed_file = SeedFiles.upsert_pending("my-bucket", "foods/missing.json")

    assert {:error, :timeout} =
             perform_job(SeedFileImportWorker, %{
               "seed_file_id" => seed_file.id,
               "bucket" => "my-bucket",
               "key" => "foods/missing.json"
             })

    reloaded = Repo.get!(SeedFile, seed_file.id)
    assert reloaded.status == "failed"
    assert reloaded.error =~ "timeout"
  end

  test "enqueue/2 upserts a pending row and inserts a job" do
    assert {:ok, _job} = SeedFileImportWorker.enqueue("my-bucket", "foods/c.json")

    assert %SeedFile{status: "pending"} =
             Repo.get_by(SeedFile, bucket: "my-bucket", key: "foods/c.json")

    assert_enqueued(
      worker: SeedFileImportWorker,
      args: %{bucket: "my-bucket", key: "foods/c.json"}
    )
  end

  test "enqueue/2 is unique per key while a job is in flight" do
    assert {:ok, _} = SeedFileImportWorker.enqueue("my-bucket", "foods/dup.json")
    assert {:ok, job2} = SeedFileImportWorker.enqueue("my-bucket", "foods/dup.json")

    # The second insert is deduplicated by the unique constraint (conflict: true).
    assert job2.conflict?
  end
end
