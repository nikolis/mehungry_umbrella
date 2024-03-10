defmodule Mehungry.Posts.CommentAnswerVote do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comment_answer_votes" do
    field :positive, :boolean, default: false
    belongs_to :comment_answer, Mehungry.Posts.CommentAnswer
    belongs_to :user, Mehungry.Accounts.User

    timestamps()
  end

  @doc false
  def changeset(comment_answer_vote, attrs) do
    comment_answer_vote
    |> cast(attrs, [:positive, :user_id, :comment_answer_id])
    |> validate_required([:positive, :user_id, :comment_answer_id])
  end
end
