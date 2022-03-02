defmodule Mehungry.Food.CategoryTranslation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "category_translations" do
    field :name, :string

    belongs_to :category, Mehungry.Food.Category

    belongs_to :language, Mehungry.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(cat_trans, attrs) do
    cat_trans
    |> cast(attrs, [:name, :language_name])
    |> validate_required([:name, :language_name])
    |> unique_constraint(:name)
  end
end
