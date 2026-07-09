defmodule Mehungry.ObanWorkers.OffDeltaSyncWorker do
  @moduledoc """
  Weekly Open Food Facts delta sync (Oban cron, Mondays 4am UTC).

  Fetches OFF's delta index (daily files named `products_<from>_<to>.json.gz`,
  ~14 days retained), applies every file newer than the stored watermark
  oldest-first, and advances the watermark per file so a mid-run crash resumes
  where it left off. Rows older than what is already stored are skipped by
  the upsert's freshness guard.

  Limitation (v1): upsert-only — products deleted or marked obsolete on OFF
  are not removed locally. Cleaning those up needs either a `states_tags`
  obsolete filter or a periodic full re-import.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3, unique: [period: 3600]

  require Logger

  alias Mehungry.FoodProducts
  alias Mehungry.OpenFoodFacts.BulkImporter

  @sync_key "delta"
  @filename_format ~r/^products_(\d+)_(\d+)\.json\.gz$/

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case off_client().fetch_delta_index() do
      {:ok, filenames} ->
        filenames
        |> pending_files()
        |> apply_files()

      {:error, reason} ->
        Logger.warning("[OffDeltaSync] Could not fetch delta index: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Delta files newer than the watermark, oldest first.
  defp pending_files(filenames) do
    watermark = watermark_timestamp()

    filenames
    |> Enum.flat_map(fn filename ->
      case Regex.run(@filename_format, filename) do
        [_, _from, to] -> [{String.to_integer(to), filename}]
        nil -> []
      end
    end)
    |> Enum.filter(fn {to, _} -> to > watermark end)
    |> Enum.sort()
    |> Enum.map(fn {_, filename} -> filename end)
  end

  defp watermark_timestamp do
    case FoodProducts.get_sync_state(@sync_key) do
      %{last_processed_file: filename} when is_binary(filename) ->
        case Regex.run(@filename_format, filename) do
          [_, _from, to] -> String.to_integer(to)
          nil -> 0
        end

      _ ->
        0
    end
  end

  defp apply_files([]) do
    Logger.info("[OffDeltaSync] No new delta files")
    :ok
  end

  defp apply_files(filenames) do
    Logger.info("[OffDeltaSync] Applying #{length(filenames)} delta file(s)")

    Enum.reduce_while(filenames, :ok, fn filename, :ok ->
      case apply_file(filename) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_file(filename) do
    dest = Path.join(System.tmp_dir!(), filename)

    try do
      with :ok <- off_client().download_delta(filename, dest),
           {:ok, %{imported: imported}} <- BulkImporter.import_file(dest) do
        {:ok, _} =
          FoodProducts.put_sync_state(@sync_key, %{
            last_processed_file: filename,
            last_synced_at: DateTime.utc_now() |> DateTime.truncate(:second),
            products_upserted: previous_upserted() + imported
          })

        Logger.info("[OffDeltaSync] Applied #{filename}: #{imported} products")
        :ok
      else
        {:error, reason} ->
          Logger.warning("[OffDeltaSync] Failed on #{filename}: #{inspect(reason)}")
          {:error, reason}
      end
    after
      File.rm(dest)
    end
  end

  defp previous_upserted do
    case FoodProducts.get_sync_state(@sync_key) do
      %{products_upserted: n} when is_integer(n) -> n
      _ -> 0
    end
  end

  defp off_client do
    Application.get_env(:mehungry, :off_client, Mehungry.OpenFoodFacts.Client)
  end
end
