defmodule Mehungry.Test.Testinger do
  use Ecto.Schema
  import Ecto.Changeset

  schema "testingers" do
    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(testinger, attrs) do
    testinger
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
