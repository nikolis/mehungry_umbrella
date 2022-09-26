defmodule MehungryApi.LikeView do
  use MehungryApi, :view

  alias MehungryApi.LikeView
  alias Mehungry.Food.Like

  def render("likes.json", %{likes: likes}) do
    %{data: render_many(likes, LikeView, "like.json")}
  end

  def render("like.json", %{like: like}) do
    %{recipe_id: like.recipe_id, user_id: like.user_id}
  end
end
