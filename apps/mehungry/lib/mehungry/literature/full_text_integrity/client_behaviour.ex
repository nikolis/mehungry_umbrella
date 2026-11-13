defmodule Mehungry.Literature.FullTextIntegrity.ClientBehaviour do
  @moduledoc """
  The seam `Mehungry.Literature.FullTextIntegrity` resolves a PMID's PMC Open Access
  status + license through (config key `:europepmc_client`). Stubbed in tests.
  """

  @doc """
  Resolve a PMID. Returns `{:ok, %{oa?: boolean, license: String.t() | nil,
  license_url: String.t() | nil, pmcid: String.t() | nil}}` or `{:error, reason}`.
  """
  @callback lookup(pmid :: String.t()) ::
              {:ok, %{optional(atom()) => any()}} | {:error, term()}
end
