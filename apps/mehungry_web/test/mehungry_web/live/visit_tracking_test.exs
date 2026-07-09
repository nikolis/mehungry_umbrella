defmodule MehungryWeb.VisitTrackingTest do
  @moduledoc false

  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.FoodFixtures

  alias Mehungry.{Accounts, Food, Meta}

  # Private-range IPs are used throughout so create_visit's async country
  # enrichment (Meta.local_ip?/1) never makes an outbound HTTP call in tests.

  defp accept_consent(conn) do
    Plug.Test.init_test_session(conn, %{"cookie_consent" => "accepted"})
  end

  # LiveViewTest reads connect info from this private. The session must be
  # captured into the map, so call this after all session mutations.
  defp put_connect_info(conn, info) do
    info =
      info
      |> Map.put_new(:session, Plug.Conn.get_session(conn))
      |> Map.put_new(:user_agent, "test-agent")

    Plug.Conn.put_private(conn, :live_view_connect_info, info)
  end

  defp recent_ips do
    Meta.recent_visits(10) |> Enum.map(& &1.ip_address)
  end

  describe "visit recording on mount" do
    test "records a visit with an IPv4 peer address", %{conn: conn} do
      conn =
        conn
        |> accept_consent()
        |> put_connect_info(%{peer_data: %{address: {192, 168, 1, 77}}})

      {:ok, _view, _html} = live(conn, ~p"/home")

      assert "192.168.1.77" in recent_ips()
    end

    test "records a visit with an IPv6 peer address", %{conn: conn} do
      conn =
        conn
        |> accept_consent()
        |> put_connect_info(%{peer_data: %{address: {0, 0, 0, 0, 0, 0, 0, 1}}})

      {:ok, _view, _html} = live(conn, ~p"/home")

      assert "::1" in recent_ips()
    end

    test "prefers the first x-forwarded-for hop over the socket peer", %{conn: conn} do
      conn =
        conn
        |> accept_consent()
        |> put_connect_info(%{
          peer_data: %{address: {172, 31, 0, 9}},
          x_headers: [{"x-forwarded-for", "10.55.44.33, 172.31.0.9"}]
        })

      {:ok, _view, _html} = live(conn, ~p"/home")

      assert "10.55.44.33" in recent_ips()
      refute "172.31.0.9" in recent_ips()
    end

    test "does not record a visit without consent", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> put_connect_info(%{peer_data: %{address: {192, 168, 1, 78}}})

      {:ok, _view, _html} = live(conn, ~p"/home")

      assert recent_ips() == []
    end
  end

  describe "visit recording on patch navigation" do
    setup [:register_and_log_in_user]

    test "records a second visit with user attribution when patching to a recipe", %{
      conn: conn,
      user: user
    } do
      profile = Accounts.get_user_profile_by_user_id(user.id)
      {:ok, _} = Accounts.update_user_profile(profile, %{onboarding_level: 1})

      recipe = recipe_fixture(user)
      Food.create_post_from_recipe(recipe)

      conn =
        conn
        |> accept_consent()
        |> put_connect_info(%{peer_data: %{address: {192, 168, 1, 80}}})

      {:ok, view, _html} = live(conn, ~p"/home")
      assert length(Meta.recent_visits(10)) == 1

      view |> element("#card-link-to-recipe-#{recipe.id}") |> render_click()

      visits = Meta.recent_visits(10)
      assert length(visits) == 2
      assert Enum.all?(visits, &(&1.ip_address == "192.168.1.80"))
      assert Enum.any?(visits, fn v -> get_in(v.details, ["user_email"]) == user.email end)
    end
  end
end
