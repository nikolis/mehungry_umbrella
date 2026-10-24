defmodule Mehungry.MealBlueprints.BlueprintTranslation do
  @moduledoc """
  A per-language translation of a `Mehungry.MealBlueprints.Blueprint`'s
  user-facing text (`name` + `description`). Keyed on `(blueprint_id,
  language_name)` and driven, like every other `*_translation` table, by the
  `Mehungry.Languages.TranslationRegistry` descriptor and the professional
  translation hub. `status` follows the shared `"ai_draft" → "verified"`
  lifecycle; only verified rows are shown at read-time (see
  `MealBlueprints.localize_blueprints/2`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "meal_blueprint_translations" do
    field :name, :string
    field :description, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :blueprint, Mehungry.MealBlueprints.Blueprint

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(blueprint_trans, attrs) do
    blueprint_trans
    |> cast(attrs, [
      :name,
      :description,
      :language_name,
      :blueprint_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint([:blueprint_id, :language_name])
  end
end
