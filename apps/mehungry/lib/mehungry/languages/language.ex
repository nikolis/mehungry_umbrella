defmodule Mehungry.Languages.Language do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:name, :string, autogenerate: false}
  schema "languages" do
    timestamps()
  end

  def changeset(language, attrs) do
    language
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
