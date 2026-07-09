defmodule Mehungry.OpenFoodFacts.ClientBehaviour do
  @moduledoc """
  Contract for the Open Food Facts HTTP client, so tests can swap in a stub
  via the `:off_client` app config key (same pattern as `:social_media_publisher`).
  """

  @callback fetch_product(barcode :: String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_delta_index() :: {:ok, [String.t()]} | {:error, term()}
  @callback download_delta(filename :: String.t(), dest_path :: Path.t()) ::
              :ok | {:error, term()}
  @callback download_dump(dest_path :: Path.t()) :: :ok | {:error, term()}
end
