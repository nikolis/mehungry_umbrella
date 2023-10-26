defmodule Mehungry.Inventory.BasketSelectionParams do
  @moduledoc false

  import Ecto.Changeset

  defstruct [:selection_map]

  @types %{selection_map: :map}

  def changeset(%__MODULE__{} = basket_selection_params, attrs) do
    {basket_selection_params, @types}
    |> cast(attrs, Map.keys(@types))
    |> validate_required([:selection_map])
  end
end
