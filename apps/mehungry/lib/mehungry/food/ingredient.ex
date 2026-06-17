defmodule Mehungry.Food.Ingredient do
  @moduledoc false
  alias Mehungry.Food.{IngredientPortion, IngredientNutrient}

  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredients" do
    field :description, :string
    field :name, :string
    field :url, :string
    # Add this line
    field :search_name, :string

    field :food_class, :string
    field :nutrient_conversion_factors, {:array, :map}, default: []
    field :publication_date, :string
    field :nutrient_data_source, :string

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
      :food_class,
      :nutrient_data_source
    ])
    |> cast_assoc(:ingredient_portions,
      with: &Mehungry.Food.IngredientPortion.changeset/2,
      sort_param: :ingredient_portions_sort,
      drop_param: :ingredient_portions_drop
    )
    # Add this line
    |> update_search_name()
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

  defp update_search_name(changeset) do
    if name = get_change(changeset, :name) do
      search_name = normalize_string(name)
      put_change(changeset, :search_name, search_name)
    else
      changeset
    end
  end

  def normalize_string(str) when is_binary(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  def normalize_string(_), do: ""
end
