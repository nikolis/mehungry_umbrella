defmodule MehungryWeb.NutritionistHandleControllerTest do
  use MehungryWeb.ConnCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.Professionals

  defp public_profile_with_handle(handle) do
    user = user_fixture()

    {:ok, profile} =
      Professionals.create_professional_profile(%{
        user_id: user.id,
        specialization: "Dietitian",
        display_name: "Maria Papadaki",
        city: "Rethymno",
        bio: "Clinical dietitian.",
        is_public: true,
        handle: handle
      })

    profile
  end

  describe "GET /@:handle" do
    test "301-redirects a known public handle to the canonical profile", %{conn: conn} do
      profile = public_profile_with_handle("maria_p")

      conn = get(conn, "/@maria_p")

      assert conn.status == 301
      assert redirected_to(conn, 301) == "/en/nutritionists/#{profile.slug}"
    end

    test "resolves case-insensitively", %{conn: conn} do
      profile = public_profile_with_handle("maria_p")

      conn = get(conn, "/@MARIA_P")
      assert redirected_to(conn, 301) == "/en/nutritionists/#{profile.slug}"
    end

    test "404s an unknown handle", %{conn: conn} do
      conn = get(conn, "/@nobody")
      assert conn.status == 404
    end

    test "404s a private profile's handle", %{conn: conn} do
      user = user_fixture()

      {:ok, _private} =
        Professionals.create_professional_profile(%{
          user_id: user.id,
          specialization: "Dietitian",
          handle: "hidden"
        })

      conn = get(conn, "/@hidden")
      assert conn.status == 404
    end

    test "404s a single-segment path without the @ prefix", %{conn: conn} do
      conn = get(conn, "/some-random-word")
      assert conn.status == 404
    end
  end

  describe "does not shadow real routes" do
    test "/foods still resolves", %{conn: conn} do
      conn = get(conn, "/foods")
      assert conn.status == 200
    end
  end
end
