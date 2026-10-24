defmodule MehungryWeb.Api.V1.DeviceTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Notifications

  setup :register_and_log_in_api_user

  test "POST /me/devices registers the token", %{conn: conn, user: user} do
    assert %{"data" => %{"ok" => true}} =
             conn
             |> post(~p"/api/v1/me/devices", %{"expo_token" => "ExpoTok[a]", "platform" => "ios"})
             |> json_response(201)

    assert Notifications.tokens_for_user(user.id) == ["ExpoTok[a]"]
  end

  test "re-POST upserts (no duplicate)", %{conn: conn, user: user} do
    conn
    |> post(~p"/api/v1/me/devices", %{"expo_token" => "ExpoTok[a]", "platform" => "ios"})
    |> json_response(201)

    conn
    |> post(~p"/api/v1/me/devices", %{"expo_token" => "ExpoTok[a]", "platform" => "android"})
    |> json_response(201)

    assert Notifications.tokens_for_user(user.id) == ["ExpoTok[a]"]
  end

  test "DELETE /me/devices/:token removes it", %{conn: conn, user: user} do
    {:ok, _} = Notifications.register_device(user.id, "ExpoTok[a]", "ios")

    assert conn |> delete(~p"/api/v1/me/devices/#{"ExpoTok[a]"}") |> response(204)
    assert Notifications.tokens_for_user(user.id) == []
  end

  test "requires auth" do
    anon = Phoenix.ConnTest.build_conn()

    assert anon
           |> post(~p"/api/v1/me/devices", %{"expo_token" => "x", "platform" => "ios"})
           |> json_response(401)
  end
end
