defmodule Mehungry.Food.MeasurementUnitTranslation do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  schema "measurement_unit_translations" do
    field :name, :string
    field :alternate_name, :string

    belongs_to :language, Mehungry.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    belongs_to :measurement_unit, Mehungry.Food.Measurement_unit

    timestamps()
  end

  def changeset(mu_trans, attrs) do
    mu_trans
    |> cast(attrs, [:language_name, :name, :alternate_name])
    |> validate_required([:language_name, :name])
  end
end
