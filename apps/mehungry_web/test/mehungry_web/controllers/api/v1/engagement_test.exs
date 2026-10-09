defmodule MehungryWeb.Api.V1.EngagementTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures

  setup :register_and_log_in_api_user

  defp recipe_with_post do
    author = AccountsFixtures.user_fixture()
    recipe = FoodFixtures.recipe_fixture(author)
    {:ok, _post} = Mehungry.Posts.create_post(recipe)
    recipe
  end

  test "like then unlike a recipe", %{conn: conn} do
    recipe = recipe_with_post()

    conn1 = post(conn, ~p"/api/v1/recipes/#{recipe.id}/like")
    assert %{"data" => %{"likes_count" => 1, "liked_by_me" => true}} = json_response(conn1, 200)

    conn2 = delete(conn, ~p"/api/v1/recipes/#{recipe.id}/like")
    assert %{"data" => %{"likes_count" => 0, "liked_by_me" => false}} = json_response(conn2, 200)
  end

  test "save then unsave a recipe", %{conn: conn} do
    recipe = FoodFixtures.recipe_fixture(AccountsFixtures.user_fixture())

    assert %{"data" => %{"saved_by_me" => true}} =
             conn |> post(~p"/api/v1/recipes/#{recipe.id}/save") |> json_response(200)

    assert %{"data" => %{"saved_by_me" => false}} =
             conn |> delete(~p"/api/v1/recipes/#{recipe.id}/save") |> json_response(200)
  end

  test "comment on a recipe and list it", %{conn: conn} do
    recipe = FoodFixtures.recipe_fixture(AccountsFixtures.user_fixture())

    assert %{"data" => %{"id" => _, "text" => "Great!"}} =
             conn
             |> post(~p"/api/v1/recipes/#{recipe.id}/comments", %{"text" => "Great!"})
             |> json_response(201)

    assert %{"data" => [%{"text" => "Great!"} | _]} =
             conn |> get(~p"/api/v1/recipes/#{recipe.id}/comments") |> json_response(200)
  end

  test "follow then unfollow a user", %{conn: conn} do
    target = AccountsFixtures.user_fixture()

    assert %{"data" => %{"following" => true, "followers_count" => 1}} =
             conn |> post(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)

    assert %{"data" => %{"following" => false, "followers_count" => 0}} =
             conn |> delete(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)
  end

  test "me/recipes created tab", %{conn: conn, user: user} do
    _r = FoodFixtures.recipe_fixture(user)
    assert %{"data" => cards} = conn |> get(~p"/api/v1/me/recipes?tab=created") |> json_response(200)
    assert length(cards) >= 1
  end
end
