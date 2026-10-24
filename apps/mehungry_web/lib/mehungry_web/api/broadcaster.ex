defmodule MehungryWeb.Api.Broadcaster do
  @moduledoc """
  Thin wrapper over `MehungryWeb.Endpoint.broadcast/3` for the mobile channels
  (spec §13). REST actions call these after they mutate state so connected
  clients get live updates. Kept in the web layer so the `Posts`/`Food` contexts
  stay web-agnostic.
  """

  alias MehungryWeb.Endpoint

  def recipe_created(card), do: Endpoint.broadcast("feed:lobby", "recipe_created", %{recipe: card})

  def recipe_liked(recipe_id, likes_count) do
    Endpoint.broadcast("feed:lobby", "recipe_liked", %{recipe_id: recipe_id, likes_count: likes_count})
    Endpoint.broadcast("recipe:#{recipe_id}", "like_changed", %{likes_count: likes_count})
  end

  def comment_created(recipe_id, comment) do
    Endpoint.broadcast("recipe:#{recipe_id}", "comment_created", %{comment: comment})
  end
end
