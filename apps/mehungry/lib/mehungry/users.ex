defmodule Mehungry.Users do
  import Ecto.Query

  alias Mehungry.Repo
  alias Mehungry.Food.Recipe
  alias Mehungry.Accounts.User
  alias Mehungry.Accounts.UserRecipe
  alias Mehungry.Accounts.UserPost
  alias Mehungry.Accounts.UserFollow
  alias Mehungry.Accounts.UserCategoryRule
  alias Mehungry.Food.FoodRestrictionType
  alias Mehungry.Food.FoodRestrictionType
  alias Mehungry.Food.RecipeUtils

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

  def calculate_recipe_grading(nil, user) do
    0
  end

  def calculate_recipe_grading(recipe, user) do
    recipe_grade =
      RecipeUtils.calculate_recipe_ingredient_categories_array(recipe)
      |> Enum.map(fn x -> {x, 1.0} end)
      |> Enum.into(%{})

    user_pref_array = calculate_user_pref_table(user)
    user_follows = list_user_follows(user)
    user_follows = Enum.map(user_follows, fn x -> x.follow_id end)

    grade =
      Enum.reduce(recipe_grade, 1, fn {key, _grade}, acc ->
        case Map.get(user_pref_array, key) do
          nil ->
            1 * acc

          grade ->
            grade * acc
        end
      end)

    case recipe.user_id in user_follows do
      false ->
        grade

      true ->
        if(grade > 0) do
          grade + 4
        else
          grade
        end
    end
  end

  def calculate_user_pref_table(user) do
    user_category_rules = get_user_category_rules(user)

    Enum.map(user_category_rules, fn x ->
      title = x.category.name
      grade = Map.get(@restrictions, x.food_restriction_type.title)
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

  def create_user_restriction_type(attrs) do
    %FoodRestrictionType{}
    |> Mehungry.Food.FoodRestrictionType.changeset(attrs)
    |> Repo.insert()
  end

  def list_food_restriction_types() do
    FoodRestrictionType
    |> Repo.all()
  end

  def create_user_category_rule(attrs) do
    %UserCategoryRule{}
    |> UserCategoryRule.changeset(attrs)
    |> Repo.insert()
  end

  def list_user_category_rules() do
    UserCategoryRule
    |> Repo.all()
  end

  def get_user_category_rulles(%User{} = user) do
    from(u_c_r in UserCategoryRule,
      where: u_c_r.user_id == ^user.id
    )
    |> Repo.all()
    |> Repo.preload([:category])
  end

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
end
