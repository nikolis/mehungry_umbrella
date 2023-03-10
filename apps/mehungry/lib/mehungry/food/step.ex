defmodule Mehungry.Food.Step do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :title, :string
    field :description, :string
    field :index, :integer

    field :delete, :boolean, virtual: true
    field :temp_id, :string, virtual: true
  end

  def changeset(step, attrs) do
    step
    # So its persisted
    #|> Map.put(:temp_id, step.temp_id || attrs["temp_id"])
    |> cast(attrs, [:title, :description, :delete, :temp_id, :index])
    |> validate_required([:description, :index])
    |> maybe_mark_for_deletion()
  end

  defp maybe_mark_for_deletion(%{data: %{id: nil}} = changeset), do: changeset

  defp maybe_mark_for_deletion(changeset) do
    if get_change(changeset, :delete) do
      %{changeset | action: :delete}
    else
      changeset
    end
  end
end
