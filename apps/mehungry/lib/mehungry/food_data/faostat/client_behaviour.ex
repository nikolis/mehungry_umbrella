defmodule Mehungry.FoodData.Faostat.ClientBehaviour do
  @moduledoc """
  Behaviour for the FAOSTAT production loader, so the bundled-file read can be swapped
  for a stub in tests via the `:faostat_client` config key.
  """

  @doc """
  Loads the bundled FAOSTAT production rows as a list of maps:
  `%{item_code: "515", item: "Apples", area: "China", year: 2022, value_tonnes: 47571100.0}`.
  """
  @callback load_rows() :: {:ok, [map()]} | {:error, term()}
end
