defmodule MehungryWeb.Api.V1.FeedController do
  @moduledoc """
  The Home tab feed (spec §4) — community recipe cards, newest/most-relevant
  first, paginated. Backed by `Posts.list_posts/1` (personalized when a bearer
  token is present via `MaybeApiAuthPlug`).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserContent
  alias Mehungry.Posts
  alias Mehungry.Users
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.BlueprintMatch
  alias MehungryWeb.Api.V1.RecipeJSON

  def index(conn, params) do
    user = conn.assigns[:current_user]
    lang = language(conn, params, user)

    posts =
      user
      |> Posts.list_posts()
      |> Posts.localize_for_language(lang)

    {page_posts, meta} = Pagination.paginate_list(posts, Pagination.params(params))

    page_posts = Posts.preload_engagement(page_posts)

    ctx = viewer_ctx(user)
    carded_posts = Enum.filter(page_posts, & &1.reference)

    blueprint = BlueprintMatch.blueprint(conn, params)
    reports = BlueprintMatch.recipe_reports(blueprint, Enum.map(carded_posts, & &1.reference))

    cards =
      Enum.map(carded_posts, fn post ->
        match = BlueprintMatch.block(blueprint, reports, post.reference.id)
        RecipeJSON.feed_card(post, ctx, match)
      end)

    json(conn, data(cards, meta))
  end

  defp viewer_ctx(nil), do: %{user_id: nil, follow_ids: [], saved_recipe_ids: []}

  defp viewer_ctx(user) do
    %{
      user_id: user.id,
      follow_ids: Users.list_user_follows(user) |> Enum.map(& &1.follow_id),
      saved_recipe_ids: UserContent.list_user_saved_recipe_ids(user)
    }
  end

  defp language(conn, params, user) do
    params["lang"] ||
      case Plug.Conn.get_req_header(conn, "accept-language") do
        [lang | _] when is_binary(lang) -> String.slice(lang, 0, 2)
        _ -> nil
      end ||
      (user && Accounts.get_user_language(user.id)) || "en"
  end
end
