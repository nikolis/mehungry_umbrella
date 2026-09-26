defmodule Mehungry.Extractor.ClientBehaviour do
  @moduledoc """
  Contract for the batch-PMID analysis extractor (`mehungry_extractor`'s
  `POST /analyze`), so tests can swap in a stub via the `:extractor_client`
  app config key (same pattern as `:instagram_client`).
  """

  @callback analyze(pmids :: [String.t()], opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end
