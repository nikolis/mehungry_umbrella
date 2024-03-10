defmodule Mehungry.Posts.PostUpvote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_upvotes" do
    field :post_id, :id
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(post_upvote, attrs) do
    post_upvote
    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
  end
end
