defmodule Mehungry.Meta.Visit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "visits" do
    field :details, :map
    field :ip_address, :string
    field :session_key, :string

    timestamps()
  end

  @doc false
  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:ip_address, :session_key, :details])
    |> validate_required([:ip_address])
  end
end
