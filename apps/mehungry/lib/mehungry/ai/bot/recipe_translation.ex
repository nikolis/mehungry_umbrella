defmodule Mehungry.AI.Bot.RecipeTranslation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "recipe_translations" do
    field :title, :string
    field :description, :string
    field :steps, {:array, :map}, default: []

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :recipe, Mehungry.Food.Recipe

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [
      :recipe_id,
      :language_name,
      :title,
      :description,
      :steps,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:recipe_id, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint([:recipe_id, :language_name])
    |> foreign_key_constraint(:recipe_id)
  end
end
