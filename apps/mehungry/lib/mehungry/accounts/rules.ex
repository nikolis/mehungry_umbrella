defmodule Mehungry.Accounts.Rules do
  @moduledoc """
  User dietary rules: per-category and per-ingredient restriction rules.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Accounts.{UserCategoryRule, UserIngredientRule}

  def list_user_category_rules do
    Repo.all(UserCategoryRule)
  end

  def get_user_category_rule!(id), do: Repo.get!(UserCategoryRule, id)

  def create_user_category_rule(attrs \\ %{}) do
    %UserCategoryRule{}
    |> UserCategoryRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_user_category_rule(%UserCategoryRule{} = user_category_rule, attrs) do
    user_category_rule
    |> UserCategoryRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_user_category_rule(%UserCategoryRule{} = user_category_rule) do
    Repo.delete(user_category_rule)
  end

  def change_user_category_rule(%UserCategoryRule{} = user_category_rule, attrs \\ %{}) do
    UserCategoryRule.changeset(user_category_rule, attrs)
  end

  def list_user_ingredient_rules do
    Repo.all(UserIngredientRule)
  end

  def get_user_ingredient_rule!(id), do: Repo.get!(UserIngredientRule, id)

  def create_user_ingredient_rule(attrs \\ %{}) do
    %UserIngredientRule{}
    |> UserIngredientRule.changeset(attrs)
    |> Repo.insert()
  end

  def update_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule, attrs) do
    user_ingredient_rule
    |> UserIngredientRule.changeset(attrs)
    |> Repo.update()
  end

  def delete_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule) do
    Repo.delete(user_ingredient_rule)
  end

  def change_user_ingredient_rule(%UserIngredientRule{} = user_ingredient_rule, attrs \\ %{}) do
    UserIngredientRule.changeset(user_ingredient_rule, attrs)
  end
end
