defmodule Mehungry.Food.Compound do
  @moduledoc """
  A bioactive / chemical compound as a first-class reference entity —
  oxalates, lectins, phytates, histamine, polyphenols, FODMAP compounds,
  purines, salicylates, and other bioactives (e.g. "Oxalate", "Sulforaphane").

  A shared registry (like `Nutrient`): a single compound row carries its canonical
  `name`, its `synonyms`, and its structural `properties` (molecular formula,
  SMILES, IUPAC name, InChI). Its cross-database identity (MeSH, PubChem CID,
  ChEBI, CAS, HMDB, InChIKey) lives in the normalized `CompoundIdentifier` table,
  and it is linked to many ingredients through `IngredientCompoundRelationship`.

  This layer represents **scientific facts only** — it never stores
  recommendations, limits, or dietary advice.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.{CompoundIdentifier, IngredientCompoundRelationship}

  @compound_types ~w(oxalate lectin phytate histamine polyphenol fodmap purine salicylate other)

  @type t :: %__MODULE__{}

  schema "compounds" do
    field :name, :string
    field :compound_type, :string
    field :synonyms, {:array, :string}, default: []
    # Structural descriptors (molecular_formula, smiles, isomeric_smiles, inchi,
    # iupac_name…). Not identifiers — those are rows in compound_identifiers.
    field :properties, :map, default: %{}
    field :description, :string

    has_many :identifiers, CompoundIdentifier
    has_many :ingredient_compound_relationships, IngredientCompoundRelationship
    # Read-only literature link (written only via Mehungry.Literature).
    has_many :study_links, Mehungry.Literature.StudyCompound
    # Read-only health-recommendation link (written only via Mehungry.Health).
    has_many :condition_recommendations, Mehungry.Health.CompoundRecommendation

    timestamps()
  end

  def changeset(compound, attrs) do
    compound
    |> cast(attrs, [
      :name,
      :compound_type,
      :synonyms,
      :properties,
      :description
    ])
    |> validate_required([:name, :compound_type])
    |> validate_inclusion(:compound_type, @compound_types)
    |> unique_constraint(:name)
  end
end
