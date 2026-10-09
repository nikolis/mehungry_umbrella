defmodule MehungryWeb.Api.V1.EngagementController do
  @moduledoc """
  Social engagement on recipes (spec §5): like/unlike, save/unsave, comments,
  comment answers, and comment votes. Delegates to `Posts` and
  `Accounts.UserContent`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Accounts.UserContent
  alias Mehungry.Posts
  alias MehungryWeb.Api.Broadcaster

  action_fallback MehungryWeb.Api.V1.FallbackController

  # ── likes ────────────────────────────────────────────────────────────────

  def like(conn, %{"recipe_id" => recipe_id}) do
    id = to_int(recipe_id)

    with {:ok, engagement} <- Posts.like_recipe(id, uid(conn)) do
      Broadcaster.recipe_liked(id, engagement.likes_count)
      json(conn, data(%{likes_count: engagement.likes_count, liked_by_me: true}))
    end
  end

  def unlike(conn, %{"recipe_id" => recipe_id}) do
    id = to_int(recipe_id)

    with {:ok, engagement} <- Posts.unlike_recipe(id, uid(conn)) do
      Broadcaster.recipe_liked(id, engagement.likes_count)
      json(conn, data(%{likes_count: engagement.likes_count, liked_by_me: false}))
    end
  end

  # ── saves (the profile "saved" tab) ───────────────────────────────────────

  def save(conn, %{"recipe_id" => recipe_id}) do
    UserContent.save_user_recipe(uid(conn), to_int(recipe_id))
    json(conn, data(%{saved_by_me: true}))
  end

  def unsave(conn, %{"recipe_id" => recipe_id}) do
    UserContent.remove_user_saved_recipe(uid(conn), to_int(recipe_id))
    json(conn, data(%{saved_by_me: false}))
  end

  # ── comments ───────────────────────────────────────────────────────────────

  def comments(conn, %{"recipe_id" => recipe_id}) do
    comments = Mehungry.Food.get_recipe_comments(to_int(recipe_id))
    json(conn, data(Enum.map(comments, &comment_json/1)))
  end

  def create_comment(conn, %{"recipe_id" => recipe_id, "text" => text}) do
    attrs = %{"text" => text, "recipe_id" => to_int(recipe_id), "user_id" => uid(conn)}

    with {:ok, comment} <- Posts.create_comment(attrs) do
      loaded = load_comment(comment.id)
      Broadcaster.comment_created(to_int(recipe_id), comment_json(loaded))
      conn |> put_status(:created) |> json(data(comment_json(loaded)))
    end
  end

  def create_answer(conn, %{"comment_id" => comment_id, "text" => text}) do
    attrs = %{"text" => text, "comment_id" => to_int(comment_id), "user_id" => uid(conn)}

    with {:ok, answer} <- Posts.create_comment_answer(attrs) do
      conn
      |> put_status(:created)
      |> json(data(%{id: answer.id, text: answer.text, comment_id: answer.comment_id}))
    end
  end

  def vote_comment(conn, %{"comment_id" => comment_id} = params) do
    reaction = to_bool(params["value"])
    Posts.vote_comment(to_int(comment_id), uid(conn), reaction)
    json(conn, data(%{comment_id: to_int(comment_id), positive: reaction}))
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp comment_json(comment) do
    %{
      id: comment.id,
      text: comment.text,
      user: user_stub(comment.user),
      inserted_at: utc(comment.inserted_at),
      answers_count: length(loaded(comment.comment_answers)),
      votes_count: length(loaded(comment.votes))
    }
  end

  defp load_comment(id), do: Mehungry.Posts.get_comment!(id) |> Mehungry.Repo.preload([:user, :votes, :comment_answers])

  defp user_stub(%Ecto.Association.NotLoaded{}), do: nil
  defp user_stub(nil), do: nil
  defp user_stub(user), do: %{id: user.id, alias: user.name || user.email, avatar_url: user.profile_pic}

  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []

  defp uid(conn), do: conn.assigns.current_user.id

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)

  # vote_comment/3 expects the string "true"/"false" (its internal get_positive).
  defp to_bool(1), do: "true"
  defp to_bool("1"), do: "true"
  defp to_bool(true), do: "true"
  defp to_bool(_), do: "false"
end
