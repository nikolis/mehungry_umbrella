defmodule Mehungry.Accounts.UserContent do
  @moduledoc """
  A user's saved and created content: saved recipes/posts, follows, and
  created-recipe listings.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Accounts.{User, UserFollow, UserPost, UserRecipe}
  alias Mehungry.Food.{FoodRestrictionType, Recipe}

  def save_user_recipe(user_id, recipe_id) do
    attrs = %{user_id: user_id, recipe_id: recipe_id}

    %UserRecipe{}
    |> UserRecipe.changeset(attrs)
    |> Repo.insert()
  end

  def save_user_post(user_id, post_id) do
    attrs = %{user_id: user_id, post_id: post_id}

    %UserPost{}
    |> UserPost.changeset(attrs)
    |> Repo.insert()
  end

  def save_user_follow(user_id, follow_id) when is_integer(user_id) and is_integer(follow_id) do
    attrs = %{user_id: user_id, follow_id: follow_id}

    %UserFollow{}
    |> UserFollow.changeset(attrs)
    |> Repo.insert()
  end

  def remove_user_saved_recipe(user_id, recipe_id)
      when is_integer(user_id) and is_integer(recipe_id) do
    from(u_r in UserRecipe,
      where:
        u_r.user_id == ^user_id and
          u_r.recipe_id == ^recipe_id
    )
    |> Repo.delete_all()
  end

  def remove_user_saved_post(user_id, post_id)
      when is_integer(user_id) and is_integer(post_id) do
    from(u_p in UserPost,
      where:
        u_p.user_id == ^user_id and
          u_p.post_id == ^post_id
    )
    |> Repo.delete_all()
  end

  def remove_user_follow(user_id, follow_id)
      when is_integer(user_id) and is_integer(follow_id) do
    from(u_f in UserFollow,
      where:
        u_f.user_id == ^user_id and
          u_f.follow_id == ^follow_id
    )
    |> Repo.delete_all()
  end

  def list_user_saved_recipes(%User{} = user) do
    from(u_r in UserRecipe,
      where: u_r.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload(recipe: [:recipe_ingredients])
  end

  def list_user_saved_recipe_ids(%User{} = user) do
    from(u_r in UserRecipe,
      where: u_r.user_id == ^user.id,
      select: u_r.recipe_id
    )
    |> Repo.all()
  end

  def list_user_follows(%User{} = user) do
    from(u_f in UserFollow,
      where: u_f.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload(:follow)
  end

  def list_user_saved_posts(%User{} = user) do
    from(u_p in UserPost,
      where: u_p.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload(post: [:recipe])
  end

  def list_user_created_recipes(%User{} = user) do
    from(recipe in Recipe,
      where: recipe.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload(:recipe_ingredients)
  end

  def remove_recipe_from_users_list(%User{} = user, %Recipe{} = recipe) do
    from(u_r in UserRecipe,
      where:
        u_r.user_id == ^user.id and
          u_r.recipe_id == ^recipe.id
    )
    |> Repo.delete()
  end

  def create_user_restriction_type(attrs) do
    %FoodRestrictionType{}
    |> Mehungry.Food.FoodRestrictionType.changeset(attrs)
    |> Repo.insert()
  end
end
