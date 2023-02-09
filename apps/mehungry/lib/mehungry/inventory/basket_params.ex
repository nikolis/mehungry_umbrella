defmodule Mehungry.Inventory.BasketParams do
  defstruct [:start_dt, :end_dt]
  @types %{start_dt: :date, end_dt: :date}
  import Ecto.Changeset

  def changeset(%__MODULE__{} = basket, attrs) do
    {basket, @types}
    |> cast(attrs, Map.keys(@types))
    |> validate_required([:start_dt, :end_dt])
  end
end
