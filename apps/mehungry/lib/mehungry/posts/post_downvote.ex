defmodule Mehungry.Posts.PostDownvote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "post_downvotes" do
    field :post_id, :id
    field :user_id, :id

    timestamps()
  end

  @doc false
  def changeset(post_downvote, attrs) do
    post_downvote
    |> cast(attrs, [:user_id, :post_id])
    |> validate_required([:user_id, :post_id])
  end
end
