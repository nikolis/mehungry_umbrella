defmodule Mehungry.Posts.CommentVote do
  alias Mehungry.Posts.CommentVote
  use Ecto.Schema
  import Ecto.Changeset

  schema "comment_votes" do
    field :positive, :boolean, default: false

    belongs_to :comment, Mehungry.Posts.Comment
    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(comment_vote, attrs) do
    comment_vote
    |> cast(attrs, [:positive, :user_id, :comment_id])
    |> validate_required([:positive, :user_id, :comment_id])
  end
end
