defmodule Mehungry.Extractor.Client do
  @moduledoc """
  HTTP client for the `mehungry_extractor` batch-PMID analysis service
  (`POST /analyze`). The target URL and optional auth token are the UI-managed
  connection from `Mehungry.Extractor.connection/0` (editable at
  `/professional/health`), falling back to the `:extractor_base_url` config
  (`EXTRACTOR_BASE_URL` env var). Default `http://127.0.0.1:8000`. When a token is
  set it is sent as an `Authorization: Bearer <token>` header.

  The service is a deterministic evidence engine: it ingests each PMID (fetching
  from PubMed/PMC on first use — hence the generous timeout), extracts claims, and
  returns per-paper observations (each tracing back to a verbatim source span)
  alongside the detected topic core and outliers. See `mehungry_extractor/docs/api.md`.
  """

  @behaviour Mehungry.Extractor.ClientBehaviour

  # First call fetches every un-cached PMID from PubMed/PMC, so a large batch can take
  # many minutes. Generous default, overridable via the `:extractor_timeout_ms` config
  # key (env var EXTRACTOR_TIMEOUT_MS).
  @default_timeout_ms 900_000

  @doc """
  Analyze a batch of PMIDs (up to 200). `pmids` are strings; `opts` may carry the
  API's `options` map under the `:options` key. Returns `{:ok, response_map}` on 200,
  `{:error, {:invalid, body}}` on a 422 validation failure, or `{:error, reason}`.
  """
  @impl true
  def analyze(pmids, opts \\ []) when is_list(pmids) do
    body =
      %{pmids: pmids}
      |> maybe_put_options(Keyword.get(opts, :options))
      |> Jason.encode!()

    http_opts = [recv_timeout: timeout_ms(), timeout: timeout_ms()]
    {base_url, auth_token} = Mehungry.Extractor.connection()

    case HTTPoison.post(base_url <> "/analyze", body, headers(auth_token), http_opts) do
      {:ok, %{status_code: 200, body: resp}} ->
        decode(resp)

      {:ok, %{status_code: 422, body: resp}} ->
        {:error, {:invalid, resp}}

      {:ok, %{status_code: code, body: resp}} ->
        {:error, {:http, code, resp}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:network, reason}}
    end
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp maybe_put_options(body, nil), do: body
  defp maybe_put_options(body, options) when is_map(options), do: Map.put(body, :options, options)

  defp decode(resp) do
    case Jason.decode(resp) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, {:bad_json, resp}}
    end
  end

  defp headers(auth_token) do
    base = [
      {"content-type", "application/json"},
      {"accept", "application/json"}
    ]

    if is_binary(auth_token) and auth_token != "",
      do: [{"authorization", "Bearer " <> auth_token} | base],
      else: base
  end

  defp timeout_ms, do: Application.get_env(:mehungry, :extractor_timeout_ms, @default_timeout_ms)
end
