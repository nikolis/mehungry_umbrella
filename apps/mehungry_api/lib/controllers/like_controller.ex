defmodule MehungryApi.LikeController do
  use MehungryApi, :controller

  alias Mehungry.Accounts
  alias Mehungry.Food

  def get_likes(conn, %{"user_id" => user_id}) do
    user = Accounts.get_user!(user_id)
    likes = Food.get_user_likes(user_id)
    render(conn, "likes.json", likes: likes)
  end
end
