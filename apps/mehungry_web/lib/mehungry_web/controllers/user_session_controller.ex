defmodule MehungryWeb.UserSessionController do
  use MehungryWeb, :controller

  alias Mehungry.Accounts
  alias MehungryWeb.UserAuth
  alias MehungryWeb.Router.Helpers, as: Routes

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        render(conn, "new.html", error_message: "Invalid email or password")

      %{confirmed_at: nil} = user ->
        {:ok, _} =
          Accounts.deliver_user_confirmation_instructions(
            user,
            &Routes.user_confirmation_url(conn, :edit, &1)
          )

        conn
        |> put_flash(
          :error,
          "You need to confirm your email first. We've resent the confirmation link."
        )
        |> render("new.html", error_message: nil)

      user ->
        UserAuth.log_in_user(conn, user, user_params)
    end
  end

  def delete_user(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.delete_user()
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
