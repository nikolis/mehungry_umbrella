defmodule MehungrySeasonality.Comext.ClientBehaviour do
  @moduledoc "Seam for the Eurostat Comext monthly trade API."

  @doc """
  The raw JSON-stat dataset of monthly import quantities for one reporter country and
  one HS/CN product code, all partner countries, between two `"YYYY-MM"` periods.
  """
  @callback monthly_imports(
              country_iso :: String.t(),
              code :: String.t(),
              since :: String.t(),
              until :: String.t()
            ) :: {:ok, map()} | {:error, term()}
end
