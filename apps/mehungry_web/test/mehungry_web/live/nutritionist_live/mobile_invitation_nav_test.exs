defmodule MehungryWeb.NutritionistLive.MobileInvitationNavTest do
  @moduledoc """
  Regression test for reaching the nutritionist-invitation accept page on mobile.

  The mobile bottom bar was reshaped into five flat tabs and no longer carries a
  dedicated invitation bell. The relationship ("Nutritionist") tab routes a
  logged-in client to `/my-nutritionist`, which surfaces any pending invitations
  as an accept/decline banner. This guards that a client with a pending invite
  can still always reach the accept UI on mobile through that hub.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Professionals

  # Nav links are locale-prefixed; a logged-in user with no locale in the URL
  # defaults to "en".
  @mobile_nutritionist_tab "#nav_bar_mobile a[href='/en/my-nutritionist']"

  setup do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()
    %{nutritionist: nutritionist, client: client}
  end

  test "mobile nav routes to the my-nutritionist hub, where a pending invite can be accepted",
       %{conn: conn, nutritionist: nutritionist, client: client} do
    {:ok, _invitation} = Professionals.invite_client(nutritionist.id, client.email)

    {:ok, view, _html} = live(log_in_user(conn, client), ~p"/home")
    assert has_element?(view, @mobile_nutritionist_tab)

    # Following that tab lands on the hub, which shows the pending invite's
    # accept control — the reachable path that replaced the dedicated bell.
    {:ok, hub, html} = live(log_in_user(conn, client), "/en/my-nutritionist")
    assert html =~ "invited you to connect"
    assert has_element?(hub, "button[phx-click='accept_invitation']")
  end

  test "the Nutritionist tab is present for a logged-in client", %{conn: conn, client: client} do
    {:ok, view, _html} = live(log_in_user(conn, client), ~p"/home")
    assert has_element?(view, @mobile_nutritionist_tab)
  end
end
