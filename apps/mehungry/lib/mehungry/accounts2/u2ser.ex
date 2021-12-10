defmodule Mehungry.Accounts2.U2ser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "u2sers" do
    field :age, :integer
    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(u2ser, attrs) do
    u2ser
    |> cast(attrs, [:name, :age])
    |> validate_required([:name, :age])
  end
end
