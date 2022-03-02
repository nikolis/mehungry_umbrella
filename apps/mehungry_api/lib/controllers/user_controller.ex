defmodule MehungryApi.UserController do
  use MehungryApi, :controller

  alias MehungryApi.Guardian

  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Account.User
  alias MehungryApi.LikeView

  action_fallback(MehungryApi.FallbackController)

  def get(conn, %{"id" => user_id}) do
    user = Accounts.get_user!(user_id)
    render(conn, "show.json", user: user)
  end

  def search_user(conn, %{"user_name" => user_name}) do
    users = Food.list_users()
    render(conn, "index.json", users: users)
  end

  def follow_user(conn, %{"user_id" => user_id}) do
    user_follower = Guardian.Plug.current_resource(conn)
    user_to_follow = Accounts.get_user!(user_id)

    {:ok, follow} =
      Accounts.follow_user(%{user_id: user_follower.id, follow_id: user_to_follow.id})

    render(conn, "show.json", user_to_follow)
  end

  def update(conn, %{"user" => user_params}) do
    user_auth = Guardian.Plug.current_resource(conn)
    user = Accounts.get_user!(user_auth.id)

    case Accounts.update_user(user, user_params) do
      {:ok, user} ->
        conn
        |> render("show.json", user: user)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:bad_request)
        |> render("error.json", changeset: changeset)
    end
  end
end
