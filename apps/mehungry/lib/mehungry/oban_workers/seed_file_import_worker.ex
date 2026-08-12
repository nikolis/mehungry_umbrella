defmodule Mehungry.ObanWorkers.SeedFileImportWorker do
  @moduledoc """
  Seeds one S3 ingredient file into the USDA dataset, tracked end-to-end.

  One job == one file: it fetches the object's JSON (via the `:seed_file_fetcher`
  seam), parses+inserts it through `FoodParser.get_ingredients_from_json_body/1`
  (a single transaction per file), and records the outcome on the file's
  `SeedFile` row. Success returns `:ok`; failure returns `{:error, reason}` so
  Oban records the error and retries up to `max_attempts`. The durable
  `seed_files` row is what lets the S3 browser re-do only the undone files.

  Replaces the earlier fire-and-forget in-memory seed worker, which tracked
  nothing and silently dropped failures.
  """

  use Oban.Worker,
    queue: :seed_imports,
    max_attempts: 3,
    unique: [
      fields: [:args],
      keys: [:bucket, :key],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  require Logger

  alias Mehungry.FoodData.Usda.{FoodParser, SeedFileFetcher, SeedFiles}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"seed_file_id" => id, "bucket" => bucket, "key" => key}}) do
    SeedFiles.mark_processing(id)

    case fetcher().fetch(bucket, key) do
      {:ok, body} ->
        parse_and_record(id, key, body)

      {:error, reason} ->
        Logger.error("[SeedFileImport] fetch failed for #{key}: #{inspect(reason)}")
        SeedFiles.mark_failed(id, reason)
        {:error, reason}
    end
  end

  defp parse_and_record(id, key, body) do
    case FoodParser.get_ingredients_from_json_body(body) do
      {:ok, count} ->
        Logger.info("[SeedFileImport] #{key}: inserted #{count} ingredients")
        SeedFiles.mark_completed(id, count)
        :ok

      {:error, reason} ->
        Logger.error("[SeedFileImport] parse failed for #{key}: #{inspect(reason)}")
        SeedFiles.mark_failed(id, reason)
        {:error, reason}
    end
  end

  defp fetcher do
    Application.get_env(:mehungry, :seed_file_fetcher, SeedFileFetcher)
  end

  @doc """
  Enqueues (or resets) a seed file and returns the `Oban.insert` result. Upserts
  the tracking row to `pending` first so the UI reflects the queued state even
  before the job starts.
  """
  def enqueue(bucket, key) do
    seed_file = SeedFiles.upsert_pending(bucket, key)

    %{seed_file_id: seed_file.id, bucket: bucket, key: key}
    |> new()
    |> Oban.insert()
  end
end
