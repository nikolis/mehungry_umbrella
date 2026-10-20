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
    data(%{
      id: user.id,
      email: user.email,
      alias: alias_for(user, profile),
      avatar_url: user.profile_pic,
      intro: profile && profile.intro,
      language_preference: (profile && profile.language_preference) || "en",
      daily_calorie_target: profile && profile.daily_calorie_target,
      onboarding_level: (profile && profile.onboarding_level) || 0,
      tier: tier,
      quota: quota,
      counts: counts
    })
  end

  @doc "Minimal public profile (spec §6 `GET /users/:id`)."
  def public(%{user: user, profile: profile, counts: counts} = args) do
    data(Map.put(public_map(user, profile, counts), :following, Map.get(args, :following, false)))
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
