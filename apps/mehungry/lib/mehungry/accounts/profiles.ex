defmodule Mehungry.Accounts.Profiles do
  @moduledoc """
  User profiles: CRUD, language preference, and the follower/saved-recipe
  count helpers shown on profile pages.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Accounts.{
    User,
    UserContent,
    UserFollow,
    UserProfile
  }

  def list_user_profiles do
    Repo.all(UserProfile)
  end

  def get_user_profile!(id), do: Repo.get!(UserProfile, id)

  def get_user_profile_by_user_id(id) do
    from(p in UserProfile,
      where: p.user_id == ^id
    )
    |> Repo.one()
    |> Repo.preload([:user_category_rules, :user_ingredient_rules])
  end

  def create_user_profile(attrs \\ %{}) do
    %UserProfile{}
    |> UserProfile.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Ensures the user has a profile, creating an empty one when missing.
  Returns the profile.
  """
  def create_user_profile_if_needed(user) do
    case get_user_profile_by_user_id(user.id) do
      nil ->
        {:ok, _profile} =
          create_user_profile(%{user_id: user.id, user_category_rules: []})

        get_user_profile_by_user_id(user.id)

      profile ->
        profile
    end
  end

  def update_user_profile(%UserProfile{} = user_profile, attrs) do
    user_profile
    |> UserProfile.changeset(attrs)
    |> Repo.update()
  end

  def update_user_language(%UserProfile{} = profile, lang) when lang in ["en", "el"] do
    profile
    |> UserProfile.changeset(%{language_preference: lang})
    |> Repo.update()
  end

  @doc """
  Persists (or clears, with `nil`) the meal blueprint the user is following on
  their calendar. A targeted single-column update (`Ecto.Changeset.change/2`) so
  it doesn't re-run the full profile validations/assoc casts.
  """
  def set_followed_blueprint(%UserProfile{} = profile, blueprint_id) do
    profile
    |> Ecto.Changeset.change(followed_blueprint_id: blueprint_id)
    |> Repo.update()
  end

  @doc """
  Persists the user's personal "foods I avoid" list. Accepts a list of strings
  (or a newline/comma-separated string), trims blanks and dedups before saving.
  A targeted single-column update so it skips the full profile validations.
  """
  def set_avoid_foods(%UserProfile{} = profile, foods) do
    profile
    |> Ecto.Changeset.change(avoid_foods: clean_food_list(foods))
    |> Repo.update()
  end

  @doc "Normalizes a raw avoid-foods value into a trimmed, de-duplicated list."
  def clean_food_list(foods) when is_binary(foods) do
    foods |> String.split(~r/[\n,]/) |> clean_food_list()
  end

  def clean_food_list(foods) when is_list(foods) do
    foods
    |> Enum.map(&(&1 |> to_string() |> String.trim()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def clean_food_list(_), do: []

  def get_user_language(user_id) do
    case get_user_profile_by_user_id(user_id) do
      nil -> "en"
      profile -> profile.language_preference || "en"
    end
  end

  def delete_user_profile(%UserProfile{} = user_profile) do
    Repo.delete(user_profile)
  end

  @doc """
  The diet "mode" a user has set on their profile — `:vegan | :vegetarian | nil`
  — read from the profile's persisted `diet` column. Used to switch on
  `#vegan`/`#vegetarian` filtering on the browse and home feeds. `nil` for
  guests, omnivores, and pescatarians (no `#pescatarian` recipe tag to filter on).
  """
  def diet_mode(nil), do: nil
  def diet_mode(%User{id: user_id}), do: diet_mode(user_id)

  def diet_mode(user_id) when is_integer(user_id) do
    from(p in UserProfile, where: p.user_id == ^user_id, select: p.diet)
    |> Repo.one()
    |> diet_mode_for_diet()
  end

  @doc "Maps a profile `diet` value to the feed-filter mode (`:vegan | :vegetarian | nil`)."
  def diet_mode_for_diet("vegan"), do: :vegan
  def diet_mode_for_diet("vegetarian"), do: :vegetarian
  def diet_mode_for_diet(_), do: nil

  def change_user_profile(%UserProfile{} = user_profile, attrs \\ %{}) do
    UserProfile.changeset(user_profile, attrs)
  end

  def get_user_essentials(nil), do: {nil, [], []}

  def get_user_essentials(%User{} = user) do
    user_profile = get_user_profile_by_user_id(user.id)
    user_follows = UserContent.list_user_follows(user)

    # Only the recipe ids are needed here; use the id-only query so we don't
    # load full recipes and preload their recipe_ingredients on every mount.
    user_recipes = UserContent.list_user_saved_recipe_ids(user)

    {user_profile, user_follows, user_recipes}
  end

  def count_user_following(nil), do: nil

  def count_user_following(user_id) do
    from(u_fo in UserFollow,
      where: u_fo.user_id == ^user_id,
      select: count(u_fo.id)
    )
    |> Repo.one()
  end

  def count_user_followers(nil), do: nil

  def count_user_followers(user_id) do
    from(u_fo in UserFollow,
      where: u_fo.follow_id == ^user_id,
      select: count(u_fo.id)
    )
    |> Repo.one()
  end

  def count_user_saved_recipes(nil), do: nil

  def count_user_saved_recipes(user_id) do
    from(u_re in Mehungry.Accounts.UserRecipe,
      where: u_re.user_id == ^user_id,
      select: count(u_re.id)
    )
    |> Repo.one()
  end
end
