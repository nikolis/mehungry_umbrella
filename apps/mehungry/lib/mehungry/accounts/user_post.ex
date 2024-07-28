defmodule Mehungry.Accounts.UserPost do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mehungry.Accounts.User
  alias Mehungry.Posts.Post

  schema "user_posts" do
    belongs_to :user, User
    belongs_to :post, Post

    timestamps()
  end

  @doc false
  def changeset(user_post, attrs) do
    user_post
    |> cast(attrs, [
      :user_id,
      :post_id
    ])
    |> validate_required([:user_id, :post_id])
  end
end
