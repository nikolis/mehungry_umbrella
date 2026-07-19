defmodule Mehungry.Food.Engagement do
  @moduledoc """
  User engagement with recipes: likes, comments, and annotations.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Like, Recipe}

  def get_user_likes(user_id) do
    query =
      from a in Like,
        where: a.user_id == ^user_id

    Repo.all(query)
  end

  def like_recipe(user_id, recipe_id) do
    %Like{recipe_id: recipe_id, user_id: user_id}
    |> Repo.insert()
  end

  def count_user_liked_recipes(nil), do: nil

  def count_user_liked_recipes(user_id) do
    from(l in Like,
      where: l.user_id == ^user_id,
      select: count(l.id)
    )
    |> Repo.one()
  end

  def get_recipe_comments(recipe_id) do
    from(c in Mehungry.Posts.Comment, where: c.recipe_id == ^recipe_id)
    |> Repo.all()
    |> Repo.preload([:user, :votes, [comment_answers: :user]])
  end

  def list_annotations(%Recipe{} = recipe) do
    Repo.all(
      from a in Ecto.assoc(recipe, :annotations),
        order_by: [asc: a.at, asc: a.id],
        limit: 500,
        preload: [:user]
    )
  end
end
