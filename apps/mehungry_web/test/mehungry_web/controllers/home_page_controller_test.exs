defmodule MehungryWeb.HomePageControllerTest do
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Subscriptions

  describe "GET / (role-aware landing)" do
    test "anonymous visitors see the nutritionist-led landing page", %{conn: conn} do
      conn = get(conn, "/")
      assert redirected_to(conn) =~ "/welcome"
    end

    test "logged-in consumers land on the consumer home feed", %{conn: conn} do
      user = Mehungry.AccountsFixtures.user_fixture()
      conn = conn |> log_in_user(user) |> get("/")

      target = redirected_to(conn)
      assert target =~ "/home"
      refute target == "/nutritionist"
    end

    test "logged-in nutritionists (pro) land on their practice dashboard", %{conn: conn} do
      user = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _sub} = Subscriptions.grant_nutritionist(user.id)

      conn = conn |> log_in_user(user) |> get("/")
      assert redirected_to(conn) == "/nutritionist"
    end
  end
end
