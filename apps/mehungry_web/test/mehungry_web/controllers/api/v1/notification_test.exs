defmodule MehungryWeb.Api.V1.NotificationTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures
  alias Mehungry.Notifications

  setup :register_and_log_in_api_user

  describe "inbox endpoints" do
    test "GET /me/notifications returns the viewer's notifications, newest first",
         %{conn: conn, user: me} do
      actor = AccountsFixtures.user_fixture()
      {:ok, _} = Notifications.create(me.id, "follow", actor_id: actor.id)

      {:ok, _} =
        Notifications.create(me.id, "comment",
          actor_id: actor.id,
          subject_type: "recipe",
          subject_id: 9,
          data: %{"recipe_title" => "Soup"}
        )

      assert %{"data" => [first, second], "meta" => %{"has_more" => false}} =
               conn |> get(~p"/api/v1/me/notifications") |> json_response(200)

      assert first["type"] == "comment"
      assert first["subject"] == %{"type" => "recipe", "id" => 9}
      assert first["actor"]["id"] == actor.id
      assert first["read"] == false
      assert second["type"] == "follow"
    end

    test "unread_count and read", %{conn: conn, user: me} do
      actor = AccountsFixtures.user_fixture()
      {:ok, _} = Notifications.create(me.id, "comment", actor_id: actor.id, subject_id: 1)
      {:ok, _} = Notifications.create(me.id, "comment", actor_id: actor.id, subject_id: 2)

      assert %{"data" => %{"count" => 2}} =
               conn |> get(~p"/api/v1/me/notifications/unread_count") |> json_response(200)

      assert %{"data" => %{"unread_count" => 0}} =
               conn |> post(~p"/api/v1/me/notifications/read") |> json_response(200)

      assert %{"data" => %{"count" => 0}} =
               conn |> get(~p"/api/v1/me/notifications/unread_count") |> json_response(200)
    end

    test "requires auth", %{conn: _conn} do
      anon = Phoenix.ConnTest.build_conn()
      assert anon |> get(~p"/api/v1/me/notifications") |> json_response(401)
    end
  end

  describe "emission" do
    test "following a user notifies the target (not the actor)", %{conn: conn, user: me} do
      target = AccountsFixtures.user_fixture()

      conn |> post(~p"/api/v1/users/#{target.id}/follow") |> json_response(200)

      assert [notif] = Notifications.list(target.id)
      assert notif.type == "follow"
      assert notif.actor_id == me.id
      assert notif.subject_type == "user"
      assert notif.subject_id == me.id

      # The actor gets nothing.
      assert Notifications.unread_count(me.id) == 0
    end

    test "commenting on a recipe notifies its author", %{conn: conn, user: me} do
      author = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(author)

      conn
      |> post(~p"/api/v1/recipes/#{recipe.id}/comments", %{"text" => "Looks great!"})
      |> json_response(201)

      assert [notif] = Notifications.list(author.id)
      assert notif.type == "comment"
      assert notif.actor_id == me.id
      assert notif.subject_type == "recipe"
      assert notif.subject_id == recipe.id
      assert notif.data["preview"] == "Looks great!"
    end

    test "commenting on your own recipe notifies no one", %{conn: conn, user: me} do
      recipe = FoodFixtures.recipe_fixture(me)

      conn
      |> post(~p"/api/v1/recipes/#{recipe.id}/comments", %{"text" => "note to self"})
      |> json_response(201)

      assert Notifications.unread_count(me.id) == 0
    end
  end
end
