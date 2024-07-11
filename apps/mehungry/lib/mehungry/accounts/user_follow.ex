defmodule Mehungry.Accounts.UserFollow do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "user_follows" do
    belongs_to :user, User
    belongs_to :follow, User

    timestamps()
  end

  @doc false
  def changeset(user_follow, attrs) do
    user_follow
    |> cast(attrs, [
      :user_id,
      :follow_id
    ])
    |> validate_required([:user_id, :follow_id])
  end
end
