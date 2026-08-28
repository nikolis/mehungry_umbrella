defmodule Mehungry.Professionals.ArticleReference do
  @moduledoc """
  A single scientific reference cited from an article paragraph. Polymorphic-lite:
  `reference_type` names which one of the four typed FKs is set —

    * `"study"`     → `Mehungry.Literature.ScientificStudy` (a PubMed paper)
    * `"species"`   → `Mehungry.Food.FoundementalFoodSpecies`
    * `"compound"`  → `Mehungry.Food.Compound`
    * `"condition"` → `Mehungry.Health.Condition`

  Both `article_id` (for cheap article-wide bibliography aggregation) and
  `paragraph_id` are kept; the changeset enforces that the FK matching
  `reference_type` is present.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Professionals.{Article, ArticleParagraph}

  @reference_types ~w(study species compound condition)

  @type t :: %__MODULE__{}

  schema "professional_article_references" do
    field :reference_type, :string

    belongs_to :article, Article
    belongs_to :paragraph, ArticleParagraph

    belongs_to :study, Mehungry.Literature.ScientificStudy
    belongs_to :species, Mehungry.Food.FoundementalFoodSpecies
    belongs_to :compound, Mehungry.Food.Compound
    belongs_to :condition, Mehungry.Health.Condition

    timestamps()
  end

  @fk_for %{
    "study" => :study_id,
    "species" => :species_id,
    "compound" => :compound_id,
    "condition" => :condition_id
  }

  def changeset(reference, attrs) do
    reference
    |> cast(attrs, [
      :reference_type,
      :article_id,
      :paragraph_id,
      :study_id,
      :species_id,
      :compound_id,
      :condition_id
    ])
    |> validate_required([:reference_type, :article_id, :paragraph_id])
    |> validate_inclusion(:reference_type, @reference_types)
    |> validate_typed_fk()
    |> foreign_key_constraint(:article_id)
    |> foreign_key_constraint(:paragraph_id)
    |> foreign_key_constraint(:study_id)
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:compound_id)
    |> foreign_key_constraint(:condition_id)
    |> unique_constraint([:paragraph_id, :reference_type, :study_id, :species_id, :compound_id, :condition_id],
      name: :professional_article_references_unique_target
    )
  end

  # The FK named by reference_type must be set.
  defp validate_typed_fk(changeset) do
    case get_field(changeset, :reference_type) do
      type when is_map_key(@fk_for, type) ->
        validate_required(changeset, [@fk_for[type]])

      _ ->
        changeset
    end
  end
end
