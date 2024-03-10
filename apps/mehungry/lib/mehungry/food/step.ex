defmodule Mehungry.Food.Step do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :title, :string
    field :description, :string
    field :index, :integer

    field :delete, :boolean, virtual: true
  end

  def changeset(step, attrs) do
    changeset =
      step
      |> cast(attrs, [:title, :description, :delete, :index])
      |> validate_required([:description, :index])

    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
