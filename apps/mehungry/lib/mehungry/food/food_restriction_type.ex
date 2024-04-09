defmodule Mehungry.Food.FoodRestrictionType do
  use Ecto.Schema
  import Ecto.Changeset

  schema "food_restriction_types" do
    field :alias, :string
    field :title, :string

    timestamps()
  end

  @doc false
  def changeset(food_restriction_type, attrs) do
    food_restriction_type
    |> cast(attrs, [:title, :alias])
    |> validate_required([:title, :alias])
  end
end
