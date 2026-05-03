defmodule Mehungry.Components.SearchSelect do
  use Ecto.Schema
  import Ecto.Changeset

  schema "search_selects" do
    timestamps()
  end

  @doc false
  def changeset(search_select, attrs) do
    search_select
    |> cast(attrs, [])
    |> validate_required([])
  end
end
