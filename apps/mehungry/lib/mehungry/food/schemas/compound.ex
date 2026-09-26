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
  # Curatable gate for whether a compound may ever become a dietary fact. `pending`
  # (default) is allowed but unreviewed; `non_dietary` is excluded everywhere
  # (candidate derivation + health advice); `dietary` is an admin-confirmed
  # constituent that skips the LLM plausibility gate.
  @dietary_relevance_values ~w(dietary non_dietary pending)

  @type t :: %__MODULE__{}

  schema "compounds" do
    field :name, :string
    field :compound_type, :string
    field :synonyms, {:array, :string}, default: []
    # Structural descriptors (molecular_formula, smiles, isomeric_smiles, inchi,
    # iupac_name…). Not identifiers — those are rows in compound_identifiers.
    field :properties, :map, default: %{}
    field :description, :string
    field :dietary_relevance, :string, default: "pending"

    has_many :identifiers, CompoundIdentifier
    has_many :ingredient_compound_relationships, IngredientCompoundRelationship
    # Read-only literature link (written only via Mehungry.Literature).
    has_many :study_links, Mehungry.Literature.StudyCompound
    # Read-only health-recommendation link (written only via Mehungry.Health).
    has_many :condition_recommendations, Mehungry.Health.CompoundRecommendation
    # Per-language name/description translations.
    has_many :translations, Mehungry.Food.CompoundTranslation

    timestamps()
  end

  def changeset(compound, attrs) do
    compound
    |> cast(attrs, [
      :name,
      :compound_type,
      :synonyms,
      :properties,
      :description,
      :dietary_relevance
    ])
    |> validate_required([:name, :compound_type])
    |> validate_inclusion(:compound_type, @compound_types)
    |> validate_inclusion(:dietary_relevance, @dietary_relevance_values)
    |> unique_constraint(:name)
  end
end
