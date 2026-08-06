defmodule Mehungry.Friends.Friendship do
  use Ecto.Schema
  import Ecto.Changeset

  @moduledoc """
  A symmetric friendship, stored as a single normalized row. The pair of user
  ids is always ordered `user_low_id < user_high_id` (see `normalize/2`) so that
  a friendship between A and B is one row regardless of who sent the request.
  """

  schema "friendships" do
    belongs_to :user_low, Mehungry.Accounts.User
    belongs_to :user_high, Mehungry.Accounts.User

    timestamps()
  end

  def changeset(friendship, attrs) do
    friendship
    |> cast(attrs, [:user_low_id, :user_high_id])
    |> validate_required([:user_low_id, :user_high_id])
    |> unique_constraint([:user_low_id, :user_high_id])
    |> foreign_key_constraint(:user_low_id)
    |> foreign_key_constraint(:user_high_id)
  end

  @doc "Orders a pair of user ids so the smaller is `user_low_id`."
  def normalize(user_a_id, user_b_id) do
    {min(user_a_id, user_b_id), max(user_a_id, user_b_id)}
  end
end
