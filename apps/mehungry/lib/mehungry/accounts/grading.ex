defmodule Mehungry.Accounts.Grading do
  @moduledoc """
  Personalized recipe grading: scores recipes against a user's category
  preference rules and follow graph.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Accounts.{User, UserCategoryRule, UserContent}

  @meat [
    "Poultry Products",
    "Sausages and Luncheon Meats",
    "Pork Products",
    "Beef Products",
    "Lamb, Veal, and Game Products"
  ]
  @seafood ["Finfish and Shellfish Products", "Fish"]
  @restrictions %{
    "Absolutely not" => 0,
    "Not a fun" => 0.5,
    "Neutral" => 1,
    "Fun" => 1.5,
    "Absolute fun" => 2
  }

  def calculate_recipe_grading(nil, _user) do
    0
  end

  def calculate_recipe_grading(recipe, user) do
    user_pref_table = calculate_user_pref_table(user)
    follow_ids = UserContent.list_user_follows(user) |> Enum.map(& &1.follow_id)
    calculate_recipe_grading(recipe, user_pref_table, follow_ids)
  end

  def calculate_recipe_grading(nil, _user_pref_table, _follow_ids), do: 0

  def calculate_recipe_grading(recipe, user_pref_table, follow_ids) do
    grade =
      recipe.recipe_ingredients
      |> Enum.map(fn ri -> ri.ingredient.category.name end)
      |> Enum.uniq()
      |> Enum.reduce(1.0, fn name, acc ->
        Map.get(user_pref_table, name, 1.0) * acc
      end)

    if recipe.user_id in follow_ids and grade > 0 do
      grade + 4
    else
      grade
    end
  end

  def calculate_user_pref_table(user) do
    user_category_rules = get_user_category_rules(user)

    Enum.map(user_category_rules, fn x ->
      title = x.category.name
      grade = Map.get(@restrictions, x.food_restriction_type.title, 1.0)
      {title, grade}
    end)
    |> Enum.into(%{})
  end

  def get_category_name(category) do
    if category.category.name in @meat do
      "meat"
    else
      if category.category.name in @seafood do
        "seafood"
      else
        category.category.name
      end
    end
  end

  def get_user_category_rules(user) do
    from(u_c_r in UserCategoryRule,
      where: u_c_r.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload([:category, :food_restriction_type])
  end

  def get_user_category_rulles(%User{} = user) do
    from(u_c_r in UserCategoryRule,
      where: u_c_r.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload([:category])
  end
end
