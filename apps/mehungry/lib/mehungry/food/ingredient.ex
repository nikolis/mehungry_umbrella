defmodule Mehungry.Food.Ingredient do
  @moduledoc false
  alias Mehungry.Food.{IngredientPortion, IngredientNutrient}

  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :description, :string
    field :name, :string
    field :url, :string

    field :food_class, :string
    field :nutrient_conversion_factors, {:array, :map}, default: []
    field :publication_date, :string

    belongs_to :category, Mehungry.Food.Category
    belongs_to :measurement_unit, Mehungry.Food.MeasurementUnit

    has_many :ingredient_portions, IngredientPortion
    has_many :ingredient_nutrients, IngredientNutrient
    has_many :ingredient_translation, Mehungry.Food.IngredientTranslation

    timestamps()
  end

  @doc false
  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [
      :url,
      :name,
      :description,
      :measurement_unit_id,
      :category_id,
      :nutrient_conversion_factors,
      :publication_date,
      :food_class
    ])
    |> cast_assoc(:ingredient_portions,
      with: &Mehungry.Food.IngredientPortion.changeset/2,
      sort_param: :ingredient_portions_sort,
      drop_param: :ingredient_portions_drop
    )
    |> cast_assoc(:ingredient_translation,
      with: &Mehungry.Food.IngredientTranslation.changeset/2,
      sort_param: :ingredient_translation_sort,
      drop_param: :ingredient_translation_drop
    )
    |> cast_assoc(:ingredient_nutrients,
      with: &Mehungry.Food.IngredientNutrient.changeset/2,
      sort_param: :ingredient_translation_sort,
      drop_param: :ingredient_translation_drop
    )
    |> foreign_key_constraint(:category_id)
    |> validate_required([:name, :category_id])
    |> unique_constraint([:name])
  end
end
