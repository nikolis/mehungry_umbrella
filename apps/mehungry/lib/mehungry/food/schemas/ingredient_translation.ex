defmodule Mehungry.Food.IngredientTranslation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "ingredient_translations" do
    field :name, :string
    field :description, :string
    field :url, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :ingredient, Mehungry.Food.Ingredient

    belongs_to :language, Mehungry.Languages.Language,
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
    |> cast(attrs, [
      :name,
      :language_name,
      :description,
      :url,
      :ingredient_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint(:name)
  end
end
