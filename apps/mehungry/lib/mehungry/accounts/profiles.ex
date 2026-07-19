defmodule Mehungry.Accounts.Profiles do
  @moduledoc """
  User profiles: CRUD, language preference, and the follower/saved-recipe
  count helpers shown on profile pages.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Accounts.{User, UserContent, UserFollow, UserProfile}

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

  def get_user_language(user_id) do
    case get_user_profile_by_user_id(user_id) do
      nil -> "en"
      profile -> profile.language_preference || "en"
    end
  end

  def delete_user_profile(%UserProfile{} = user_profile) do
    Repo.delete(user_profile)
  end

  def change_user_profile(%UserProfile{} = user_profile, attrs \\ %{}) do
    UserProfile.changeset(user_profile, attrs)
  end

  def get_user_essentials(nil), do: {nil, [], []}

  def get_user_essentials(%User{} = user) do
    user_profile = get_user_profile_by_user_id(user.id)
    user_follows = UserContent.list_user_follows(user)

    user_recipes = UserContent.list_user_saved_recipes(user)
    user_recipes = Enum.map(user_recipes, fn x -> x.recipe_id end)

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
