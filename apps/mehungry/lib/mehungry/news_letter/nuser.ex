defmodule Mehungry.NewsLetter.Nuser do
  use Ecto.Schema
  import Ecto.Changeset

  schema "nusers" do
    field :email, :string

    timestamps()
  end

  @doc false
  def changeset(nuser, attrs) do
    nuser
    |> cast(attrs, [:email])
    |> validate_required([:email])
  end
end
