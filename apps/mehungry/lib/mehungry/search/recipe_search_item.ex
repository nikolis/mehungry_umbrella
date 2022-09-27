defmodule Mehungry.Search.RecipeSearchItem do
  import Ecto.Changeset

  defstruct [:query_string]

  @types %{query_string: :string}

  def changeset(%__MODULE__{} = search, attrs) do
    {search, @types}
    |> cast(attrs, Map.keys(@types))
    |> validate_required([:query_string])
  end
end
