defmodule MehungryWeb.FriendsLiveTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Friends

  setup [:register_and_log_in_user]

  test "mounts and shows the empty state", %{conn: conn} do
    {:ok, _live, html} = live(conn, "/friends")
    assert html =~ "Friends"
    assert html =~ "You don&#39;t have any friends yet." or html =~ "You don't have any friends yet."
  end

  test "sending a request by email creates a pending request", %{conn: conn, user: user} do
    friend = user_fixture()

    {:ok, live, _html} = live(conn, "/friends")

    live
    |> form("form[phx-submit=send_friend_request]", %{email: friend.email, message: ""})
    |> render_submit()

    assert render(live) =~ "Requests sent"
    assert [req] = Friends.list_sent_requests(user.id)
    assert req.recipient_id == friend.id
  end

  test "accepting a received request makes them friends", %{conn: conn, user: user} do
    requester = user_fixture()
    {:ok, _req} = Friends.send_friend_request(requester.id, user.id)

    {:ok, live, html} = live(conn, "/friends")
    assert html =~ "Requests received"

    live
    |> element("button[phx-click='accept_friend_request']")
    |> render_click()

    assert Friends.friends?(user.id, requester.id)
    assert render(live) =~ "Your Friends"
  end
end
