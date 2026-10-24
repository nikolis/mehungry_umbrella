defmodule Mehungry.FoodData.UniTools.ClientBehaviour do
  @moduledoc """
  Behaviour for the UniTools dataset loader, so the bundled-file read can be
  swapped for a stub in tests via the `:unitools_client` config key.
  """

  @doc """
  Loads and JSON-decodes the full UniTools dataset with this id (the whole
  wrapper map, including its `"recipes"` array and license metadata).
  """
  @callback load_dataset(id :: String.t()) :: {:ok, map()} | {:error, term()}
end
