defmodule MehungryWeb.ProfessionalLive.UsersTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.Subscriptions

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    admin = user_fixture(%{email: @admin_email})
    conn = log_in_user(conn, admin)
    user = user_fixture()
    %{conn: conn, user: user}
  end

  test "admin grants Mehungry Plus to a user", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/professional/users")

    html =
      view
      |> element(~s{button[phx-click="grant_plus"][phx-value-id="#{user.id}"]})
      |> render_click()

    assert html =~ "Mehungry Plus tier granted."
    sub = Subscriptions.get_subscription(user.id)
    assert sub.tier == "m3hungry_plus"
    assert sub.status == "active"
    # Admin grant must stay distinguishable from a paid subscription.
    assert is_nil(sub.stripe_subscription_id)
    assert Subscriptions.pro?(user.id)
    refute Subscriptions.nutritionist?(user.id)
  end

  test "admin grants nutritionist (pro) to a user", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, "/professional/users")

    html =
      view
      |> element(~s{button[phx-click="grant_nutritionist"][phx-value-id="#{user.id}"]})
      |> render_click()

    assert html =~ "Nutritionist tier granted."
    assert Subscriptions.get_subscription(user.id).tier == "pro"
    assert Subscriptions.nutritionist?(user.id)
  end

  test "a Plus user can be upgraded to pro and revoked back to free", %{conn: conn, user: user} do
    {:ok, _sub} = Subscriptions.grant_plus(user.id)
    {:ok, view, html} = live(conn, "/professional/users")

    # Plus badge rendered; no second grant-plus button for this user.
    assert html =~ "Plus"
    refute has_element?(view, ~s{button[phx-click="grant_plus"][phx-value-id="#{user.id}"]})

    view
    |> element(~s{button[phx-click="grant_nutritionist"][phx-value-id="#{user.id}"]})
    |> render_click()

    assert Subscriptions.get_subscription(user.id).tier == "pro"

    html =
      view
      |> element(~s{button[phx-click="revoke_subscription"][phx-value-id="#{user.id}"]})
      |> render_click()

    assert html =~ "Subscription revoked."
    sub = Subscriptions.get_subscription(user.id)
    assert sub.tier == "free"
    assert sub.status == "canceled"
    refute Subscriptions.pro?(user.id)
  end

  test "revoking a Plus grant drops the user to free", %{conn: conn, user: user} do
    {:ok, _sub} = Subscriptions.grant_plus(user.id)
    {:ok, view, _html} = live(conn, "/professional/users")

    view
    |> element(~s{button[phx-click="revoke_subscription"][phx-value-id="#{user.id}"]})
    |> render_click()

    assert Subscriptions.get_subscription(user.id).tier == "free"
    refute Subscriptions.pro?(user.id)
  end
end
