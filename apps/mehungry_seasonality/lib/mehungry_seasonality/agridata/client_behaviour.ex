defmodule MehungrySeasonality.Agridata.ClientBehaviour do
  @moduledoc "Seam for the EU agri-food portal fruit & vegetable price API."

  @doc """
  Raw price-quote rows for one product in one country over the given years. A `nil`
  product returns the rows of **every** product.
  """
  @callback quotes(country_iso :: String.t(), years :: [integer()], product :: String.t() | nil) ::
              {:ok, [map()]} | {:error, term()}

  @doc "The product names the API knows."
  @callback products() :: {:ok, [String.t()]} | {:error, term()}
end
