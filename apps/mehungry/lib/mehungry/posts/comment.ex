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
    |> cast(attrs, [:text, :user_id, :recipe_id, :post_id])
    |> validate_required([:text, :user_id])
    |> validate_target()
  end

  # A comment belongs to either a recipe (recipe feed comments) or a post
  # (e.g. a WEEKLY_PLAN meal-plan post). It must be attached to exactly one of
  # them — a comment with neither anchor is rejected rather than orphaned.
  defp validate_target(changeset) do
    recipe_id = get_field(changeset, :recipe_id)
    post_id = get_field(changeset, :post_id)

    if is_nil(recipe_id) and is_nil(post_id) do
      add_error(changeset, :recipe_id, "a comment must belong to a recipe or a post")
    else
      changeset
    end
  end
end
