defmodule Mehungry.FoodData.Usda.SeedFileFetcher do
  @moduledoc """
  Fetches the raw JSON body for one S3 seed object. Split out from
  `Mehungry.ObanWorkers.SeedFileImportWorker` behind a config seam
  (`:seed_file_fetcher`, following the `:instagram_client` pattern) so the
  worker can be tested without hitting S3/network.

  The presign happens here — at fetch time, inside the job — rather than in the
  LiveView, so short-lived URLs don't expire while jobs wait in the queue.
  """

  @callback fetch(bucket :: String.t(), key :: String.t()) ::
              {:ok, binary()} | {:error, term()}

  @behaviour __MODULE__

  alias Mehungry.S3

  @impl true
  def fetch(bucket, key) do
    case S3.presigned_url(bucket, key) do
      {:ok, {:ok, url}} ->
        case HTTPoison.get(url) do
          {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
            {:ok, body}

          {:ok, %HTTPoison.Response{status_code: status}} ->
            {:error, {:http_status, status}}

          {:error, %HTTPoison.Error{reason: reason}} ->
            {:error, reason}
        end

      {:ok, {:error, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
