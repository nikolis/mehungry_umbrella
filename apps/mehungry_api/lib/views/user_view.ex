defmodule MehungryApi.UserView do
  use MehungryApi, :view

  alias MehungryApi.UserView
  alias Mehungry.Food.Like
  alias Mehungry.Accounts

  def get_user(conn, %{"id" => user_id}) do
    user = Accounts.get_user!(user_id)
    render(conn, "show.json", user: user)
  end

  def render("show.json", %{user: user}) do
    %{data: render_one(user, UserView, "user.json")}
  end

  def render("index.json", %{users: users}) do
    %{data: render_many(users, UserView, "user.json")}
  end

  def render("user.json", %{user: user}) do
    %{
      id: user.id,
      email: user.email
      # user_name: user.name,
      # facebook_id: user.facebook_id,
      # first_name: user.first_name,
      # last_name: user.last_name
    }
  end
end
