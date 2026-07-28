defmodule Mehungry.Literature.Entrez.RawResponse do
  @moduledoc """
  An append-only record of a single raw NCBI Entrez (E-utilities) payload.

  One row per successful fetch — never overwritten. Keeping the original payload
  gives us reproducibility, debugging, re-crawl capability, and protection against
  PubMed schema changes: if we later need a field we don't currently extract, we
  can backfill it from `raw_json` without re-hitting the API.

  `endpoint` records which E-utilities call produced the payload:

    * `"esearch"` — `esearch.fcgi?db=pubmed&term=...` (carries `query`)
    * `"efetch"`  — `efetch.fcgi?db=pubmed&id=...` (efetch XML is decoded to a map
      before storage so the cache stays queryable)
  """

  use Ecto.Schema

  import Ecto.Changeset

  @endpoints ~w(esearch efetch)

  schema "entrez_responses" do
    field :endpoint, :string
    field :query, :string
    field :pmid, :integer
    field :raw_json, :map
    field :retrieved_at, :utc_datetime

    timestamps()
  end

  def changeset(response, attrs) do
    response
    |> cast(attrs, [:endpoint, :query, :pmid, :raw_json, :retrieved_at])
    |> validate_required([:endpoint, :raw_json, :retrieved_at])
    |> validate_inclusion(:endpoint, @endpoints)
  end
end
