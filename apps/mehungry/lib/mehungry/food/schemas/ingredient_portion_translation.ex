defmodule Mehungry.Food.IngredientPortionTranslation do
  @moduledoc """
  Per-language translation of an `IngredientPortion`'s free-text `description`
  (e.g. "1 medium banana" → "1 μέτρια μπανάνα"). Only unit-less portions carry
  these — unit-bearing portions get their label from the shared
  `MeasurementUnitTranslation`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "ingredient_portion_translations" do
    field :description, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    belongs_to :ingredient_portion, Mehungry.Food.IngredientPortion

    timestamps()
  end

  def changeset(portion_translation, attrs) do
    portion_translation
    |> cast(attrs, [
      :language_name,
      :description,
      :ingredient_portion_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:language_name, :description])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
  end
end
