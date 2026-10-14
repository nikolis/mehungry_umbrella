defmodule MehungryWeb.TrialController do
  use MehungryWeb, :controller

  alias Mehungry.BetaSignups

  @doc """
  One-click unsubscribe from the beta-tester list. Removes the signup for the
  token and redirects back to `/trial` with a confirmation flash.
  """
  def unsubscribe(conn, %{"token" => token}) do
    case BetaSignups.remove_by_token(token) do
      nil ->
        conn
        |> put_flash(:error, "This unsubscribe link is invalid or has already been used.")
        |> redirect(to: "/trial")

      email ->
        conn
        |> put_flash(:info, "#{email} has been removed from the Mehungry testing list.")
        |> redirect(to: "/trial")
    end
  end
end
