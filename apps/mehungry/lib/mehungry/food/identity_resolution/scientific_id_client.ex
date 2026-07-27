defmodule Mehungry.Food.IdentityResolution.ScientificIdClient do
  @moduledoc """
  Behaviour for resolving a scientific (binomial) name to external identifiers.

  Given a scientific name (obtained from USDA), an implementation returns any of
  the NCBI taxonomy id, FoodOn id, Wikidata id, taxonomic rank, and synonyms it
  can find. Implementations must be defensive — a lookup failure returns
  `{:error, reason}` (or `{:ok, %{}}` for "nothing found"), never raises.

  The active implementation is chosen via the `:scientific_id_client` app-env key
  (default: `ExternalScientificIdClient`). Tests swap in a deterministic stub.
  """

  @type ids :: %{
          optional(:ncbi_taxonomy_id) => integer() | nil,
          optional(:foodon_id) => String.t() | nil,
          optional(:wikidata_id) => String.t() | nil,
          optional(:rank) => String.t() | nil,
          optional(:id_source) => String.t() | nil,
          optional(:synonyms) => [map()]
        }

  @callback resolve(scientific_name :: String.t()) :: {:ok, ids()} | {:error, term()}
end
