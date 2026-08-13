defmodule Mehungry.Food.MeasurementUnitTranslation do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "measurement_unit_translations" do
    field :name, :string
    field :alternate_name, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    timestamps()
  end

  def changeset(mu_trans, attrs) do
    mu_trans
    |> cast(attrs, [
      :language_name,
      :name,
      :alternate_name,
      :measurement_unit_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:language_name, :name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
  end
end
