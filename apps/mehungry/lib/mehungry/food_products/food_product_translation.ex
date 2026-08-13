defmodule Mehungry.FoodProducts.FoodProductTranslation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "food_product_translations" do
    field :name, :string
    field :ingredients_text, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :food_product, Mehungry.FoodProducts.FoodProduct

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
      :ingredients_text,
      :language_name,
      :food_product_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint([:food_product_id, :language_name])
  end
end
