defmodule Mehungry.Chemistry.PubChem.RawResponse do
  @moduledoc """
  An append-only record of a single raw PubChem PUG REST payload.

  One row per successful fetch — never overwritten. Keeping the original payload
  gives us reproducibility, debugging, re-import capability, and protection
  against PubChem schema changes: if we later need a field we don't currently
  extract, we can backfill it from `raw_json` without re-hitting the API.

  `endpoint` records which PUG call produced the payload:

    * `"name_cids"`  — `/compound/name/{name}/cids` (carries `requested_name`)
    * `"properties"` — `/compound/cid/{cid}/property/...`
    * `"synonyms"`   — `/compound/cid/{cid}/synonyms`
  """

  use Ecto.Schema

  import Ecto.Changeset

  @endpoints ~w(name_cids properties synonyms)

  schema "pubchem_responses" do
    field :endpoint, :string
    field :requested_name, :string
    field :cid, :integer
    field :raw_json, :map
    field :etag, :string
    field :api_version, :string
    field :retrieved_at, :utc_datetime

    timestamps()
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [
      :endpoint,
      :requested_name,
      :cid,
      :raw_json,
      :etag,
      :api_version,
      :retrieved_at
    ])
    |> validate_required([:endpoint, :raw_json, :retrieved_at])
    |> validate_inclusion(:endpoint, @endpoints)
  end
end
