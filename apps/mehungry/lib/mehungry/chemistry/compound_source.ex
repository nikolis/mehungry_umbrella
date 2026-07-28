defmodule Mehungry.Chemistry.CompoundSource do
  @moduledoc """
  Per-source provenance for a canonical `Mehungry.Food.Compound`.

  Records that a compound's chemical identity was synced from a given external
  authority — today only PubChem, tomorrow FooDB / ChEBI / HMDB. This keeps the
  domain model source-agnostic: adding a new source is a new row, never a schema
  change. `raw_response` points at the exact cached payload the sync came from.

  One row per `(compound, source_type)`, so re-syncing is an idempotent upsert.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound
  alias Mehungry.Chemistry.PubChem.RawResponse

  @source_types ~w(pubchem chebi hmdb foodb)

  schema "compound_sources" do
    field :source_type, :string
    field :external_identifier, :string
    field :last_synced_at, :utc_datetime

    belongs_to :compound, Compound
    belongs_to :raw_response, RawResponse

    timestamps()
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [
      :compound_id,
      :raw_response_id,
      :source_type,
      :external_identifier,
      :last_synced_at
    ])
    |> validate_required([:compound_id, :source_type, :external_identifier])
    |> validate_inclusion(:source_type, @source_types)
    |> unique_constraint([:compound_id, :source_type])
  end
end
