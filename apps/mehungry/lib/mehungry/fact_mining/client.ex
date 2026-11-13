defmodule Mehungry.FactMining.Client do
  @moduledoc """
  HTTP client for the external **biomed-fact-miner** service (FastAPI,
  `POST /mine`). The target URL and optional JWT/bearer token are the UI-managed
  connection from `Mehungry.FactMining.connection/0` (editable at
  `/professional/health`), falling back to the `:fact_miner_base_url` /
  `:fact_miner_auth_token` config (`FACT_MINER_BASE_URL` / `FACT_MINER_AUTH_TOKEN`
  env; default `http://127.0.0.1:8811`). When a token is set it is sent as an
  `Authorization: Bearer <token>` header.

  `mine/2` always requests `?format=json&view=public` so non-`commercial_ok`
  quotes arrive already redacted — the fail-safe public surface. The pipeline is
  synchronous and slow (LLM calls + PubMed/PMC retrieval + an internal ~3 req/s
  licence throttle), so the default timeout is generous. See
  `../biomed-fact-miner/docs/rest-api.md`.
  """

  @behaviour Mehungry.FactMining.ClientBehaviour

  # /mine runs scope → gather → extract → verify end to end (LLM + PubMed/PMC), so
  # a single call can take many seconds. Generous default, overridable via the
  # `:fact_miner_timeout_ms` config key (env FACT_MINER_TIMEOUT_MS).
  @default_timeout_ms 120_000

  # The pre-flight /health probe must be snappy — a liveness check, not a mine.
  @reachability_timeout_ms 5_000

  @impl true
  def mine(query, opts \\ []) when is_binary(query) do
    body =
      %{
        query: query,
        fetch_fulltext: Keyword.get(opts, :fetch_fulltext, true),
        max_records: Keyword.get(opts, :max_records, 200)
      }
      |> Jason.encode!()

    http_opts = [recv_timeout: timeout_ms(), timeout: timeout_ms()]
    {base_url, auth_token} = Mehungry.FactMining.connection()
    url = base_url <> "/mine?format=json&view=public"

    case HTTPoison.post(url, body, headers(auth_token), http_opts) do
      {:ok, %{status_code: 200, body: resp}} ->
        decode(resp)

      {:ok, %{status_code: 422, body: resp}} ->
        {:error, {:invalid, resp}}

      # Miner concurrency limit saturated — back off and retry after `Retry-After`.
      # The worker turns this into an Oban `{:snooze, seconds}` (doesn't burn a retry).
      {:ok, %{status_code: 429, headers: resp_headers}} ->
        {:error, {:rate_limited, retry_after_seconds(resp_headers)}}

      {:ok, %{status_code: code, body: resp}} ->
        {:error, {:http, code, resp}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:network, reason}}
    end
  end

  @impl true
  def reachable? do
    opts = [recv_timeout: @reachability_timeout_ms, timeout: @reachability_timeout_ms]
    {base_url, auth_token} = Mehungry.FactMining.connection()

    case HTTPoison.get(base_url <> "/health", headers(auth_token), opts) do
      {:ok, %HTTPoison.Response{}} -> :ok
      {:error, %HTTPoison.Error{reason: reason}} -> {:error, {:network, reason}}
    end
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  # Default/clamp for a 429 back-off when the server sends no (or an unparseable)
  # `Retry-After`. Seconds.
  @default_retry_after_s 30
  @min_retry_after_s 5

  # Read the `Retry-After` header (case-insensitive; HTTPoison headers are
  # `{name, value}` tuples). Supports the integer-seconds form; falls back to a
  # sane default, clamped to a minimum so we never hot-loop.
  defp retry_after_seconds(headers) do
    seconds =
      headers
      |> Enum.find_value(fn {name, value} ->
        if String.downcase(name) == "retry-after", do: value, else: nil
      end)
      |> parse_retry_after()

    max(seconds, @min_retry_after_s)
  end

  defp parse_retry_after(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {secs, _} when secs >= 0 -> secs
      _ -> @default_retry_after_s
    end
  end

  defp parse_retry_after(_), do: @default_retry_after_s

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

  defp timeout_ms,
    do: Application.get_env(:mehungry, :fact_miner_timeout_ms, @default_timeout_ms)
end
