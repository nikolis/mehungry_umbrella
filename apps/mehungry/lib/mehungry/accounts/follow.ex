defmodule Mehungry.Accounts.Follow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "follows" do
    field :user_id, :integer
    field :follow_id, :integer

    timestamps()
  end

  def changeset(follow, attrs) do
    follow
    |> cast(attrs, [:user_id, :follow_id])
    |> validate_required([:user_id, :follow_id])
  end
end
