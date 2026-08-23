defmodule Mehungry.Accounts.Profiles do
  @moduledoc """
  User profiles: CRUD, language preference, and the follower/saved-recipe
  count helpers shown on profile pages.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Accounts.{
    User,
    UserConditionOptIn,
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

  @doc """
  The condition ids a profile has opted into (for health-condition badges).
  """
  def list_opted_in_condition_ids(user_profile_id) do
    from(o in UserConditionOptIn,
      where: o.user_profile_id == ^user_profile_id,
      select: o.condition_id
    )
    |> Repo.all()
  end

  @doc """
  Replaces a profile's set of opted-in conditions with `condition_ids`
  (a list of ids, possibly as strings). Deletes rows no longer selected and
  inserts newly selected ones in a single transaction. Returns `:ok`.
  """
  def set_condition_opt_ins(user_profile_id, condition_ids) do
    desired =
      condition_ids
      |> List.wrap()
      |> Enum.map(&normalize_id/1)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    current = MapSet.new(list_opted_in_condition_ids(user_profile_id))

    to_add = MapSet.difference(desired, current)
    to_remove = MapSet.difference(current, desired)

    Repo.transaction(fn ->
      if MapSet.size(to_remove) > 0 do
        from(o in UserConditionOptIn,
          where:
            o.user_profile_id == ^user_profile_id and
              o.condition_id in ^MapSet.to_list(to_remove)
        )
        |> Repo.delete_all()
      end

      Enum.each(to_add, fn condition_id ->
        %UserConditionOptIn{}
        |> UserConditionOptIn.changeset(%{
          user_profile_id: user_profile_id,
          condition_id: condition_id
        })
        |> Repo.insert!()
      end)
    end)

    :ok
  end

  defp normalize_id(id) when is_integer(id), do: id

  defp normalize_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp normalize_id(_), do: nil

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
