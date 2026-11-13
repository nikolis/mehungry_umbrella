defmodule Mehungry.FactMining.ClientBehaviour do
  @moduledoc """
  Contract for the external **biomed-fact-miner** REST API (FastAPI, `POST /mine`),
  so tests can swap in a stub via the `:fact_miner_client` app config key (same
  pattern as `:extractor_client`).
  """

  @doc """
  Mine a `FactSheet` for a broad biomedical `query`. Returns `{:ok, sheet_map}` on
  a 200 (the API's `FactSheet.to_dict()` — `query`, `scope_kind`, `counts`,
  `facts`, `trace`), `{:error, {:invalid, body}}` on a 422 validation failure,
  `{:error, {:rate_limited, seconds}}` on a 429 (miner concurrency saturated — the
  worker snoozes `seconds`, from the `Retry-After` header), or `{:error, reason}`
  on any other HTTP / transport error.

  `opts` may carry `:max_records` (1–200, default 200) and `:fetch_fulltext`
  (default true).
  """
  @callback mine(query :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Cheap liveness probe used as a **pre-flight** before starting a run: `:ok` when
  the service answers `GET /health` at all, `{:error, reason}` when the link is
  dead (connection refused / timeout / DNS).
  """
  @callback reachable?() :: :ok | {:error, term()}
end
