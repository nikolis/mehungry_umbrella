defmodule Mehungry.Posts.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :text, :string

    timestamps()

    belongs_to :recipe, Mehungry.Food.Recipe
    belongs_to :user, Mehungry.Accounts.User
    belongs_to :post, Mehungry.Posts.Post 

    has_many :comment_answers, Mehungry.Posts.CommentAnswer
    has_many :votes, Mehungry.Posts.CommentVote
  end

  @doc false
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:text, :user_id, :recipe_id])
    |> validate_required([:text, :recipe_id, :user_id])
  end
end
