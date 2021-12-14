defmodule Mehungry.Food.Nutrient do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nutrients" do
    field :name, :string
    field :alternative_name, :string
    field :family, :string
    field :description, :string

    timestamps()
  end
end
