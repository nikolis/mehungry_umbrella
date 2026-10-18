defmodule MehungryWeb.Api.V1.RecipeController do
  @moduledoc """
  Recipe detail + owner CRUD (spec §4). Reads delegate to `Food.get_recipe!/1`
  and `Posts.get_recipe_engagement/2`; writes to `Food.{create,update,delete}_recipe`.
  """
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserContent
  alias Mehungry.Food
  alias Mehungry.Posts
  alias Mehungry.Users
  alias MehungryWeb.Api.V1.BlueprintMatch
  alias MehungryWeb.Api.V1.Locale
  alias MehungryWeb.Api.V1.RecipeJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def show(conn, %{"id" => id} = params) do
    user = conn.assigns[:current_user]

    with {:ok, recipe} <- fetch_recipe(id),
         :ok <- authorize_view(recipe, user) do
      engagement = Posts.get_recipe_engagement(recipe.id, user && user.id)
      match = blueprint_match(conn, params, recipe)
      json(conn, RecipeJSON.detail(recipe, engagement, viewer_ctx(user, conn, params), match))
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user

    with {:ok, %{id: id}} <- Food.create_recipe(create_attrs(params, user)) do
      recipe = Food.get_recipe!(id)
      MehungryWeb.Api.Broadcaster.recipe_created(%{id: recipe.id, title: recipe.title})

      conn
      |> put_status(:created)
      |> json(RecipeJSON.detail(recipe, Posts.get_recipe_engagement(id, user.id), viewer_ctx(user, conn, params)))
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user

    with {:ok, recipe} <- fetch_recipe(id),
         :ok <- authorize_owner(recipe, user),
         {:ok, recipe} <- Food.update_recipe(recipe, update_attrs(params)) do
      json(conn, RecipeJSON.detail(Food.get_recipe!(recipe.id), Posts.get_recipe_engagement(recipe.id, user.id), viewer_ctx(user, conn, params)))
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, recipe} <- fetch_recipe(id),
         :ok <- authorize_owner(recipe, user) do
      Food.delete_recipe(recipe.id)
      send_resp(conn, :no_content, "")
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────

  # `Food.get_recipe!/1` is Cachex-backed and returns `nil` (rather than raising)
  # for an unknown id, so guard against both.
  defp fetch_recipe(id) do
    case Food.get_recipe!(id) do
      nil -> {:error, :not_found}
      recipe -> {:ok, recipe}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    ArgumentError -> {:error, :not_found}
  end

  # Private recipes are visible only to their owner.
  defp authorize_view(%{private: true} = recipe, user) do
    if user && user.id == recipe.user_id, do: :ok, else: {:error, :not_found}
  end

  defp authorize_view(_recipe, _user), do: :ok

  defp authorize_owner(recipe, user) do
    if user && user.id == recipe.user_id, do: :ok, else: {:error, :forbidden}
  end

  defp create_attrs(params, user) do
    params
    |> Map.take(~w(title description servings difficulty cousine private original_url
                   preperation_time_lower_limit preperation_time_upper_limit
                   cooking_time_lower_limit cooking_time_upper_limit
                   recipe_ingredients steps image_url))
    |> Map.put("user_id", user.id)
    |> Map.put("language_name", recipe_language(user))
    |> put_image_from_upload(params)
  end

  defp update_attrs(params) do
    Map.take(params, ~w(title description servings difficulty cousine private original_url
                        preperation_time_lower_limit preperation_time_upper_limit
                        cooking_time_lower_limit cooking_time_upper_limit
                        recipe_ingredients steps image_url))
  end

  # image_upload_id is the S3 key returned by the presign step (spec §11). When
  # given (and no explicit image_url), treat it as the stored object key.
  defp put_image_from_upload(attrs, %{"image_upload_id" => key}) when is_binary(key) and key != "" do
    Map.put_new(attrs, "image_url", key)
  end

  defp put_image_from_upload(attrs, _params), do: attrs

  # Mirror the web create flow (create_recipe_live/index.ex): the base recipe is
  # stored as "En" and only overridden for a non-English locale (translations use
  # the locale code). This keeps `language_name` pointing at a real `languages` row.
  defp recipe_language(user) do
    case Accounts.get_user_language(user.id) do
      lang when lang not in [nil, "en"] -> lang
      _ -> "En"
    end
  end

  # Optional `?blueprint_slug=` enrichment: how this recipe lines up with the
  # blueprint's compound/nutrient targets (`nil` when no/unknown slug).
  defp blueprint_match(conn, params, recipe) do
    blueprint = BlueprintMatch.blueprint(conn, params)
    reports = BlueprintMatch.recipe_reports(blueprint, [recipe])
    BlueprintMatch.block(blueprint, reports, recipe.id)
  end

  # `:locale` is threaded into the ctx so `RecipeJSON.detail/4` can localize the
  # nutrient display names (spec §Language) — same labels as the web accordion.
  defp viewer_ctx(user, conn, params) do
    user |> base_ctx() |> Map.put(:locale, Locale.resolve(conn, params))
  end

  defp base_ctx(nil), do: %{saved_recipe_ids: [], follow_ids: []}

  defp base_ctx(user) do
    %{
      saved_recipe_ids: UserContent.list_user_saved_recipe_ids(user),
      follow_ids: Users.list_user_follows(user) |> Enum.map(& &1.follow_id)
    }
  end
end
