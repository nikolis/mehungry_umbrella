defmodule Mehungry.Food.IngredientIdentitySynonym do
  @moduledoc """
  A synonym belonging to a specific `IngredientScientificIdentity` — a scientific
  synonym, common name, foreign-language name, or abbreviation for that taxon.

  Attached per identity (not per ingredient) so each candidate carries its own
  synonym set with tight provenance; an ingredient's full synonym list is a join
  across its identities (`IdentityResolution.list_synonyms_for_ingredient/1`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Food.IngredientScientificIdentity

  @synonym_types ~w(scientific_synonym common_name foreign_name abbreviation)

  schema "ingredient_identity_synonyms" do
    field :name, :string
    field :synonym_type, :string
    field :language_name, :string
    field :source, :string

    belongs_to :scientific_identity, IngredientScientificIdentity

    timestamps()
  end

  def changeset(synonym, attrs) do
    synonym
    |> cast(attrs, [:scientific_identity_id, :name, :synonym_type, :language_name, :source])
    |> validate_required([:scientific_identity_id, :name])
    |> validate_inclusion(:synonym_type, @synonym_types)
    |> unique_constraint([:scientific_identity_id, :name, :synonym_type])
  end
end
