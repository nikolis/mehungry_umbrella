defmodule MehungrySeasonality.Comext.Client do
  @moduledoc """
  Client for **Eurostat Comext** monthly trade statistics, dataset `DS-045409`
  (EU trade since 1988 by HS2-4-6 and CN8; open, no key; reuse under CC BY 4.0 —
  attribute "Eurostat"):

      https://ec.europa.eu/eurostat/api/comext/dissemination/statistics/1.0/data/DS-045409

  One call returns import quantity (`QUANTITY_IN_100KG`) for a reporter × product code
  for every partner — individual origin countries plus aggregates such as `WORLD`.
  Intra-EU and extra-EU origins are both included.

  Swappable via `config :mehungry_seasonality, :comext_client, Stub`.
  """

  @behaviour MehungrySeasonality.Comext.ClientBehaviour

  alias MehungrySeasonality.{Countries, Http}

  @base "https://ec.europa.eu/eurostat/api/comext/dissemination/statistics/1.0/data/DS-045409"

  @doc "The configured implementation (this module unless stubbed)."
  def impl, do: Application.get_env(:mehungry_seasonality, :comext_client, __MODULE__)

  @impl true
  def monthly_imports(country_iso, code, since, until) do
    query =
      URI.encode_query([
        {"format", "JSON"},
        {"reporter", Countries.comext_code(country_iso)},
        {"product", code},
        # flow 1 = imports
        {"flow", "1"},
        {"indicators", "QUANTITY_IN_100KG"},
        {"freq", "M"},
        {"sinceTimePeriod", since},
        {"untilTimePeriod", until}
      ])

    case Http.get_json(@base <> "?" <> query) do
      {:ok, %{"value" => _} = dataset} -> {:ok, dataset}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, reason} -> {:error, reason}
    end
  end
end
