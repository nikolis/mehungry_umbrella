defmodule Mehungry.Health.ConditionTranslation do
  @moduledoc """
  A per-language translation of a `Health.Condition` name/description. One row
  per `(condition, language)`, keyed by the language's natural `name`. Carries
  the shared translation `status` (`"ai_draft"` | `"verified"`) + verification
  audit fields.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "condition_translations" do
    field :name, :string
    field :description, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :condition, Mehungry.Health.Condition

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
      :condition_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint([:condition_id, :language_name])
  end
end
