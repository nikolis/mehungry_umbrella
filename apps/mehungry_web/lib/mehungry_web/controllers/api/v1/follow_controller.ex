defmodule MehungryWeb.Api.V1.FollowController do
  @moduledoc "Follow / unfollow users (spec §5). Backed by `Accounts.UserContent`."
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Accounts
  alias Mehungry.Accounts.UserContent
  alias MehungryWeb.Api.Broadcaster

  action_fallback MehungryWeb.Api.V1.FallbackController

  def follow(conn, %{"id" => id}) do
    follower = conn.assigns.current_user
    target = to_int(id)

    case UserContent.save_user_follow(follower.id, target) do
      {:error, :self_follow} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: %{detail: "You cannot follow yourself"}})

      _ ->
        Broadcaster.notify(target, "follow", %{follower_id: follower.id})

        json(
          conn,
          data(%{following: true, followers_count: Accounts.count_user_followers(target) || 0})
        )
    end
  end

  def unfollow(conn, %{"id" => id}) do
    target = to_int(id)
    UserContent.remove_user_follow(conn.assigns.current_user.id, target)
    json(conn, data(%{following: false, followers_count: Accounts.count_user_followers(target) || 0}))
  end

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: String.to_integer(v)
end
