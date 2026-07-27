defmodule Mehungry.Food.IngredientEnrichmentSource do
  @moduledoc """
  Citation registry for scientific enrichment — the shared provenance layer.

  One source row (a DOI, dataset, URL, or book) can back many enrichment facts
  across `IngredientScientificProperty`, `IngredientClassification`, and
  `IngredientHealthAttribute`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @source_types ~w(doi url dataset book)

  schema "ingredient_enrichment_sources" do
    field :title, :string
    field :source_type, :string
    field :identifier, :string
    field :url, :string
    field :retrieved_at, :utc_datetime

    timestamps()
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:title, :source_type, :identifier, :url, :retrieved_at])
    |> validate_required([:source_type])
    |> validate_inclusion(:source_type, @source_types)
    |> unique_constraint([:source_type, :identifier])
  end
end
