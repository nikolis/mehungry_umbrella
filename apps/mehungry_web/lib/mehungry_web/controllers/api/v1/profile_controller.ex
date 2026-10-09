defmodule MehungryWeb.Api.V1.ProfileController do
  @moduledoc """
  Current-user snapshot and profile management (spec §3 `GET /me`, §6 profiles).
  """
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserContent
  alias Mehungry.Health
  alias Mehungry.Subscriptions
  alias MehungryWeb.Api.V1.UserJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  @doc "GET /api/v1/me — user + profile + tier + quota + counts."
  def me(conn, _params) do
    user = conn.assigns.current_user
    json(conn, UserJSON.me(me_snapshot(user)))
  end

  @doc "GET /api/v1/users/:id — public profile."
  def show(conn, %{"id" => id}) do
    with {:ok, user} <- fetch_user(id) do
      profile = Accounts.get_user_profile_by_user_id(user.id)

      json(
        conn,
        UserJSON.public(%{user: user, profile: profile, counts: counts_for(user)})
      )
    end
  end

  @doc "PUT /api/v1/me/profile — edit alias / intro / daily_calorie_target."
  def update(conn, params) do
    user = conn.assigns.current_user
    profile = Accounts.get_user_profile_by_user_id(user.id)

    with {:ok, _profile} <- Accounts.update_user_profile(profile, profile_attrs(params)) do
      json(conn, UserJSON.me(me_snapshot(Accounts.get_user!(user.id))))
    end
  end

  @doc "PUT /api/v1/me/language — mirrors /users/language/:lang."
  def language(conn, %{"lang" => lang}) when lang in ["en", "el"] do
    user = conn.assigns.current_user
    profile = Accounts.get_user_profile_by_user_id(user.id)

    with {:ok, _profile} <- Accounts.update_user_language(profile, lang) do
      json(conn, %{data: %{language_preference: lang}})
    end
  end

  def language(conn, _params), do: conn |> put_status(:unprocessable_entity) |> json(%{errors: %{detail: "Unsupported language"}})

  @doc "GET /api/v1/me/connected_accounts — linked social/login providers."
  def connected_accounts(conn, _params) do
    user = conn.assigns.current_user

    accounts =
      for {provider, token} <- %{
            "facebook" => user.facebook_token,
            "instagram" => user.instagram_token,
            "pinterest" => user.pinterest_token
          } do
        %{provider: provider, connected: is_map(token) and map_size(token) > 0}
      end

    json(conn, %{data: accounts})
  end

  @doc "DELETE /api/v1/me/connected_accounts/:provider — unlink a provider."
  def disconnect(conn, %{"provider" => provider}) when provider in ["facebook", "instagram", "pinterest"] do
    user = conn.assigns.current_user

    with {:ok, _user} <- Accounts.update_user_tokens(user, %{"#{provider}_token" => %{}}) do
      send_resp(conn, :no_content, "")
    end
  end

  def disconnect(conn, _params),
    do: conn |> put_status(:unprocessable_entity) |> json(%{errors: %{detail: "Unknown provider"}})

  @doc "GET /api/v1/users/:id/recipes?type=created|saved — public grid."
  def user_recipes(conn, %{"id" => id} = params) do
    with {:ok, user} <- fetch_user(id) do
      json(conn, %{data: recipe_cards(user, params["type"] || "created")})
    end
  end

  @doc "GET /api/v1/me/recipes?tab=saved|created — the Profile tab sub-tabs."
  def my_recipes(conn, params) do
    user = conn.assigns.current_user
    json(conn, %{data: recipe_cards(user, params["tab"] || "created")})
  end

  defp recipe_cards(user, "saved") do
    user
    |> UserContent.list_user_saved_recipes()
    |> Enum.map(& &1.recipe)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&MehungryWeb.Api.V1.RecipeJSON.card/1)
  end

  defp recipe_cards(user, _created) do
    user
    |> UserContent.list_user_created_recipes()
    |> Enum.map(&MehungryWeb.Api.V1.RecipeJSON.card/1)
  end

  # ── shared assembly ──────────────────────────────────────────────────────

  defp me_snapshot(user) do
    profile = Accounts.get_user_profile_by_user_id(user.id)

    %{
      user: user,
      profile: profile,
      tier: Subscriptions.get_subscription(user.id).tier,
      quota: quota_snapshot(user.id),
      counts: counts_for(user),
      condition_opt_ins: opted_in_conditions(profile)
    }
  end

  defp quota_snapshot(user_id) do
    {rg_used, rg_limit} = Subscriptions.quota_status(user_id, "recipe_generation")
    {mp_used, mp_limit} = Subscriptions.quota_status(user_id, "meal_plan")

    %{
      recipe_generations: %{used: rg_used, limit: rg_limit},
      meal_plans: %{used: mp_used, limit: mp_limit}
    }
  end

  defp counts_for(user) do
    %{
      posted_recipes: length(UserContent.list_user_created_recipes(user)),
      followers: Accounts.count_user_followers(user.id) || 0,
      following: Accounts.count_user_following(user.id) || 0
    }
  end

  defp opted_in_conditions(nil), do: []

  defp opted_in_conditions(profile) do
    profile.id
    |> Accounts.list_opted_in_condition_ids()
    |> Enum.map(&Health.get_condition/1)
    |> Enum.reject(&is_nil/1)
  end

  defp profile_attrs(params) do
    Map.take(params, ["alias", "intro", "daily_calorie_target"])
  end

  defp fetch_user(id) do
    case Accounts.get_user!(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end
end
