defmodule MehungryWeb.NutritionistLive.MobileInvitationNavTest do
  @moduledoc """
  Regression test for reaching the nutritionist-invitation accept page on mobile.

  The accept page (`/notifications/invitations`) has always worked, but the mobile
  bottom nav had no link to it — only a dead-end red dot on the profile avatar. This
  guards the dedicated bell nav item in `mobile_menu.html.heex` so a client can
  always reach the accept UI on mobile while an invitation is pending.
  """
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Mehungry.Professionals

  @mobile_invite_link "#nav_bar_mobile a[href='/notifications/invitations']"

  setup do
    nutritionist = Mehungry.AccountsFixtures.user_fixture()
    client = Mehungry.AccountsFixtures.user_fixture()
    %{nutritionist: nutritionist, client: client}
  end

  test "mobile nav links to the invitations page when the client has a pending invite",
       %{conn: conn, nutritionist: nutritionist, client: client} do
    {:ok, _invitation} = Professionals.invite_client(nutritionist.id, client.email)

    {:ok, view, _html} = live(log_in_user(conn, client), ~p"/home")

    assert has_element?(view, @mobile_invite_link)
  end

  test "mobile nav has no invitations link when there is no pending invite",
       %{conn: conn, client: client} do
    {:ok, view, _html} = live(log_in_user(conn, client), ~p"/home")

    refute has_element?(view, @mobile_invite_link)
  end
end
