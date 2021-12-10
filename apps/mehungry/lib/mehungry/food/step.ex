defmodule Mehungry.Food.Step do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :title, :string
    field :description, :string
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:title, :description])
  end


end
