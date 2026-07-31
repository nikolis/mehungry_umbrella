defmodule Mehungry.Food.ParserDismemberment do
  @moduledoc """
  A specific retail cut of the parser — the piece a `ParserPart` is butchered
  into (t bone steak, drumstick, filet).
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "parser_dismemberments" do
    field :name, :string

    has_many :aliases, Mehungry.Food.ParserDismembermentAlias, foreign_key: :dismemberment_id

    timestamps()
  end

  def changeset(dismemberment, attrs) do
    dismemberment
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
