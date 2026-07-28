defmodule Mehungry.Food.CompoundIdentifier do
  @moduledoc """
  A cross-database identity for a `Compound`, in a single normalized model.

  Each row is one external identifier in one namespace — MeSH (`mesh`), PubChem
  (`pubchem`), ChEBI (`chebi`), CAS (`cas`), HMDB (`hmdb`), Wikidata (`wikidata`),
  or the InChIKey structure hash (`inchikey`). Identifiers — not names — are the
  stable currency for integrating heterogeneous scientific data, so the registry
  is looked up and deduplicated by `(namespace, identifier)` rather than by name.

  `is_primary` marks the identifier the compound was seeded from (e.g. the MeSH id
  carried by a PubTator annotation); `source` records who asserted it. Structural
  descriptors that are not globally-unique identifiers (molecular formula, SMILES,
  IUPAC name, InChI) are *not* stored here — they live in `Compound.properties`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.Compound

  @namespaces ~w(mesh pubchem chebi cas hmdb wikidata inchikey foodb)

  @type t :: %__MODULE__{}

  schema "compound_identifiers" do
    field :namespace, :string
    field :identifier, :string
    field :is_primary, :boolean, default: false
    field :source, :string

    belongs_to :compound, Compound

    timestamps()
  end

  def changeset(compound_identifier, attrs) do
    compound_identifier
    |> cast(attrs, [:compound_id, :namespace, :identifier, :is_primary, :source])
    |> validate_required([:compound_id, :namespace, :identifier])
    |> validate_inclusion(:namespace, @namespaces)
    |> unique_constraint([:namespace, :identifier])
  end
end
