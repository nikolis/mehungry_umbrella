defmodule Mehungry.Food.NutrientTranslation do
  @moduledoc """
  A per-language translation of a `Food.Nutrient` name/alternate_name/description.
  One row per `(nutrient, language)`, keyed by the language's natural `name`.
  Carries the shared translation `status` (`"ai_draft"` | `"verified"`) +
  verification audit fields.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "nutrient_translations" do
    field :name, :string
    field :alternate_name, :string
    field :description, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :nutrient, Mehungry.Food.Nutrient

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [
      :name,
      :alternate_name,
      :description,
      :language_name,
      :nutrient_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint([:nutrient_id, :language_name])
  end
end
