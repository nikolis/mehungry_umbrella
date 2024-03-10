defmodule Mehungry.Posts.CommentAnswer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comment_answers" do
    field :text, :string

    belongs_to :comment, Mehungry.Posts.Comment
    belongs_to :user, Mehungry.Accounts.User

    has_many :votes, Mehungry.Posts.CommentAnswerVote

    timestamps()
  end

  @doc false
  def changeset(comment_answer, attrs) do
    comment_answer
    |> cast(attrs, [:text, :user_id, :comment_id])
    |> validate_required([:text, :user_id, :comment_id])
  end
end
