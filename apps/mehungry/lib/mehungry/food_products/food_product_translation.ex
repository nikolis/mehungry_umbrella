defmodule Mehungry.FoodProducts.FoodProductTranslation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "food_product_translations" do
    field :name, :string
    field :ingredients_text, :string

    belongs_to :food_product, Mehungry.FoodProducts.FoodProduct

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [:name, :ingredients_text, :language_name, :food_product_id])
    |> validate_required([:name, :language_name])
    |> unique_constraint([:food_product_id, :language_name])
  end
end
