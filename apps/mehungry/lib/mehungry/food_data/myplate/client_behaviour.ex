defmodule Mehungry.FoodData.MyPlate.ClientBehaviour do
  @moduledoc """
  Behaviour for the MyPlate (`myplate.food`) recipe API client, so the network
  calls can be swapped for a stub in tests via the `:myplate_client` config key.
  """

  @doc "Lists every recipe slug in the collection."
  @callback list_slugs() :: {:ok, [String.t()]} | {:error, term()}

  @doc "Fetches the full recipe payload for `slug`."
  @callback fetch_recipe(slug :: String.t()) :: {:ok, map()} | {:error, term()}
end
