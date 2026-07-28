defmodule Mehungry.Literature.PubTator.RawResponse do
  @moduledoc """
  An append-only record of a single raw NCBI PubTator3 payload.

  One row per successful fetch — never overwritten. Keeping the original BioC JSON
  gives reproducibility, debugging, re-annotation, and resilience against PubTator
  schema changes: if we later need an annotation field we don't currently extract,
  we backfill it from `raw_json` without re-hitting the API.

  `endpoint` records which PubTator3 call produced the payload (currently only
  `"biocjson"` — the publications export).
  """

  use Ecto.Schema

  import Ecto.Changeset

  @endpoints ~w(biocjson)

  schema "pubtator_responses" do
    field :endpoint, :string
    field :pmid, :integer
    field :raw_json, :map
    field :retrieved_at, :utc_datetime

    timestamps()
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [:endpoint, :pmid, :raw_json, :retrieved_at])
    |> validate_required([:endpoint, :raw_json, :retrieved_at])
    |> validate_inclusion(:endpoint, @endpoints)
  end
end
