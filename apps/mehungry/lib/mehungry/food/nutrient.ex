defmodule Mehungry.Food.Nutrient do
  use Ecto.Schema
  @moduledoc false

  schema "nutrients" do
    field :name, :string
    field :alternative_name, :string
    field :family, :string
    field :description, :string

    timestamps()
  end
end
