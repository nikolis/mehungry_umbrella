defmodule Mehungry.Moderation.UserBlock do
  @moduledoc """
  A one-way block: `blocker` no longer sees content authored by `blocked`. The
  blocked user is not told.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User

  schema "user_blocks" do
    belongs_to :blocker, User
    belongs_to :blocked, User

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(block, attrs) do
    block
    |> cast(attrs, [:blocker_id, :blocked_id])
    |> validate_required([:blocker_id, :blocked_id])
    |> foreign_key_constraint(:blocked_id)
    |> check_constraint(:blocked_id, name: :user_blocks_no_self_block)
  end
end
