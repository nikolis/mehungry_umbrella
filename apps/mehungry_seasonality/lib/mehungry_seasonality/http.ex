defmodule MehungrySeasonality.Http do
  @moduledoc """
  The one place this app performs HTTP. A GET returning decoded JSON, behind an
  adapter seam so parsers and clients are testable offline:

      config :mehungry_seasonality, :http_adapter, fn url, headers, opts -> … end

  No retries here — the Oban worker retries the whole unit.
  """

  @timeout_ms 20_000
  @user_agent "seasonality-fetch/1.0"

  @spec get_json(String.t()) :: {:ok, term()} | {:error, term()}
  def get_json(url) do
    headers = [{"User-Agent", @user_agent}, {"Accept", "application/json"}]

    case adapter().(url, headers, recv_timeout: @timeout_ms, follow_redirect: true) do
      {:ok, %{status_code: 200, body: body}} -> Jason.decode(body)
      {:ok, %{status_code: code, body: body}} -> {:error, {:http, code, body}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp adapter, do: Application.get_env(:mehungry_seasonality, :http_adapter, &HTTPoison.get/3)
end
