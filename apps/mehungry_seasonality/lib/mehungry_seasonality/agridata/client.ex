defmodule MehungrySeasonality.Agridata.Client do
  @moduledoc """
  Client for the European Commission **agri-food data portal** fruit & vegetable
  supply-chain price API (open, no key):

      https://api.tech.ec.europa.eu/agrifood/api/fruitAndVegetable/pricesSupplyChain

  It returns weekly/monthly price quotes per member state, product and supply-chain
  stage. This app uses only *whether* a producer-side quote exists in a period — the
  local-production signal — never the prices themselves.

  Swappable via `config :mehungry_seasonality, :agridata_client, Stub`.
  """

  @behaviour MehungrySeasonality.Agridata.ClientBehaviour

  alias MehungrySeasonality.{Countries, Http}

  @base "https://api.tech.ec.europa.eu/agrifood/api/fruitAndVegetable/pricesSupplyChain"

  @doc "The configured implementation (this module unless stubbed)."
  def impl, do: Application.get_env(:mehungry_seasonality, :agridata_client, __MODULE__)

  @impl true
  def quotes(country_iso, years, product) do
    params = %{
      "memberStateCodes" => Countries.agridata_code(country_iso),
      "years" => Enum.join(years, ",")
    }

    query = URI.encode_query(if product, do: Map.put(params, "products", product), else: params)

    case Http.get_json(@base <> "?" <> query) do
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      # The API answers 404 (not an empty list) when nothing matches the filters.
      {:error, {:http, 404, _body}} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def products do
    case Http.get_json(@base <> "/products") do
      {:ok, names} when is_list(names) -> {:ok, Enum.filter(names, &is_binary/1)}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, reason} -> {:error, reason}
    end
  end
end
