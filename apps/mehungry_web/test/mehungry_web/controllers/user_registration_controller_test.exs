defmodule MehungryWeb.UserRegistrationControllerTest do
  use MehungryWeb.ConnCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.Accounts

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, Routes.user_registration_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "Log in"
      # The password-reset link does not belong on the registration form.
      refute response =~ "Forgot your password?"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and redirects to login for email confirmation", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, Routes.user_registration_path(conn, :create), %{
          "user" => valid_user_attributes(email: email)
        })

      # The account is created but the user is NOT logged in — they must confirm
      # their email first.
      assert Accounts.get_user_by_email(email)
      refute get_session(conn, :user_token)
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "check your email"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, Routes.user_registration_path(conn, :create), %{
          "user" => %{"email" => "with spaces", "password" => "too short"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
      assert response =~ "should be at least 12 character"
    end
  end
end
