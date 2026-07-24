defmodule Mehungry.FoodData.Usda.SeedFileFetcherStub do
  @moduledoc """
  Test stand-in for `Mehungry.FoodData.Usda.SeedFileFetcher` (wired via the
  `:seed_file_fetcher` config key in `config/test.exs`) so `SeedFileImportWorker`
  tests make no S3/network calls.

  Tests control the returned body and observe calls through app config:

      Application.put_env(:mehungry, :seed_file_fetcher_stub, fn bucket, key ->
        send(test_pid, {:fetch, bucket, key})
        {:ok, ~s([{"description": "salt"}])}
      end)
      on_exit(fn -> Application.delete_env(:mehungry, :seed_file_fetcher_stub) end)

  Defaults to `{:ok, "[]"}` (a valid, empty batch) when no stub is set.
  """

  @behaviour Mehungry.FoodData.Usda.SeedFileFetcher

  @impl true
  def fetch(bucket, key) do
    case Application.get_env(:mehungry, :seed_file_fetcher_stub) do
      nil -> {:ok, "[]"}
      fun -> fun.(bucket, key)
    end
  end
end
