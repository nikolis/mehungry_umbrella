defmodule Mehungry.Extractor.ClientBehaviour do
  @moduledoc """
  Contract for the batch-PMID analysis extractor (`mehungry_extractor`'s
  `POST /analyze`), so tests can swap in a stub via the `:extractor_client`
  app config key (same pattern as `:instagram_client`).
  """

  @callback analyze(pmids :: [String.t()], opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Cheap liveness probe used as a **pre-flight** before starting a run: `:ok` when
  the service answers at all (any HTTP status), `{:error, reason}` when the link
  is dead (connection refused / timeout / DNS). Not a semantic health check.
  """
  @callback reachable?() :: :ok | {:error, term()}
end
