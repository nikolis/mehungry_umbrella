defmodule Mehungry.Food.CompoundTranslation do
  @moduledoc """
  A per-language translation of a `Food.Compound` name/description. One row per
  `(compound, language)`, keyed by the language's natural `name`. Mirrors the
  other `*_translation` schemas; carries the shared translation `status`
  (`"ai_draft"` | `"verified"`) + verification audit fields.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "compound_translations" do
    field :name, :string
    field :description, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :compound, Mehungry.Food.Compound

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
      :description,
      :language_name,
      :compound_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint([:compound_id, :language_name])
  end
end
