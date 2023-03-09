defmodule Mehungry.Tobedel.Bedel do
  use Ecto.Schema
  import Ecto.Changeset

  schema "bedels" do
    field :age, :integer
    field :url, :string

    timestamps()
  end

  @doc false
  def changeset(bedel, attrs) do
    bedel
    |> cast(attrs, [:url, :age])
    |> validate_required([:url, :age])
  end
end
