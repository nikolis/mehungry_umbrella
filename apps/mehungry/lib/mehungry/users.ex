defmodule Mehungry.Users do
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts.User
  alias Mehungry.Accounts.UserRecipe

  def save_user_recipe(%User{} = user, %Recipe{} = recipe) do
    attrs = %{user_id: user.id, recipe_id: recipe.id}

    %UserRecipe{}
    |> UserRecipe.changeset(attrs)
    |> Repo.insert()
  end

  def save_user_recipe(user_id, recipe_id) when is_integer(user_id) and is_integer(recipe_id) do
    attrs = %{user_id: user_id, recipe_id: recipe_id}

    %UserRecipe{}
    |> UserRecipe.changeset(attrs)
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

  def list_user_saved_recipes(%User{} = user) do
    from(u_r in UserRecipe,
      where: u_r.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload(recipe: [:recipe_ingredients])
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
end
