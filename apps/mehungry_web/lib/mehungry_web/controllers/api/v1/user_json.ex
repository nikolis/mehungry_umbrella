defmodule MehungryWeb.Api.V1.UserJSON do
  @moduledoc "Serializers for users, profiles, and the `me` snapshot (spec §3, §6)."

  import MehungryWeb.Api.V1.JSON.Helpers

  @doc """
  The `GET /me` payload: user + profile + tier + quota + counts + opt-ins.

  Takes a map assembled by the controller:
  `%{user:, profile:, tier:, quota:, counts:}`.
  """
  def me(%{
        user: user,
        profile: profile,
        tier: tier,
        quota: quota,
        counts: counts
      }) do
    # The nutritionist's prescription overrules the user's own target while they
    # work together — same resolver as the web calendar. `daily_calorie_target`
    # stays the user's own (editable) value.
    effective =
      Mehungry.Professionals.effective_calorie_target(
        user.id,
        profile && profile.daily_calorie_target
      )

    data(%{
      id: user.id,
      email: user.email,
      alias: alias_for(user, profile),
      avatar_url: user.profile_pic,
      intro: profile && profile.intro,
      language_preference: (profile && profile.language_preference) || "en",
      daily_calorie_target: profile && profile.daily_calorie_target,
      effective_calorie_target: effective.kcal,
      calorie_target_source: effective.source && Atom.to_string(effective.source),
      onboarding_level: (profile && profile.onboarding_level) || 0,
      tier: tier,
      quota: quota,
      counts: counts
    })
  end

  @doc "Minimal public profile (spec §6 `GET /users/:id`)."
  def public(%{user: user, profile: profile, counts: counts} = args) do
    data(
      public_map(user, profile, counts)
      |> Map.put(:following, Map.get(args, :following, false))
      |> Map.put(:blocked_by_me, Map.get(args, :blocked_by_me, false))
    )
  end

  @doc "Author sub-object embedded in recipe cards/detail."
  def author(nil), do: nil

  def author(user, recipe_count \\ nil) do
    %{
      id: user.id,
      alias: alias_for(user, nil),
      avatar_url: user.profile_pic,
      recipe_count: recipe_count
    }
  end

  @doc "The login/register auth envelope: `%{token, user}`."
  def auth(token, user, extra \\ %{}) do
    data(Map.merge(%{token: token, user: user_summary(user)}, extra))
  end

  defp public_map(user, profile, counts) do
    %{
      id: user.id,
      alias: alias_for(user, profile),
      avatar_url: user.profile_pic,
      intro: profile && profile.intro,
      counts: counts
    }
  end

  defp user_summary(user) do
    %{id: user.id, email: user.email, alias: alias_for(user, nil)}
  end

  defp alias_for(user, profile) do
    (profile && profile.alias) || user.name || user.email
  end
end
