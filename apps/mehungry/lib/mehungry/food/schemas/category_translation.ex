defmodule Mehungry.Food.CategoryTranslation do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "category_translations" do
    field :name, :string

    field :status, :string, default: "verified"
    field :verified_at, :utc_datetime
    field :verified_by_id, :id

    belongs_to :category, Mehungry.Food.Category

    belongs_to :language, Mehungry.Languages.Language,
      references: :name,
      foreign_key: :language_name,
      type: :string

    timestamps()
  end

  def changeset(cat_trans, attrs) do
    cat_trans
    |> cast(attrs, [
      :name,
      :language_name,
      :category_id,
      :status,
      :verified_at,
      :verified_by_id
    ])
    |> validate_required([:name, :language_name])
    |> validate_inclusion(:status, ["ai_draft", "verified"])
    |> unique_constraint(:name)
  end
end
