defmodule Mehungry.Food.IngredientTranslation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredient_translations" do
    field :name, :string
    field :description, :string
    field :url, :string

    belongs_to :ingredient, Mehungry.Food.Ingredient

    belongs_to :language, Mehungry.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  @spec changeset(
          {map(), map()}
          | %{
              :__struct__ => atom() | %{:__changeset__ => map(), optional(any()) => any()},
              optional(atom()) => any()
            },
          :invalid | %{optional(:__struct__) => none(), optional(atom() | binary()) => any()}
        ) :: Ecto.Changeset.t()
  def changeset(ingredient_translation, attrs) do
    ingredient_translation
    |> cast(attrs, [:name, :language_name, :description, :url])
    |> validate_required([:name, :language_name])
    |> unique_constraint(:name)
  end
end
