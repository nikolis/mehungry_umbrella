defmodule MehungryWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug-level equivalent of `MehungryWeb.AdminAuthLive` for non-LiveView routes
  such as the LiveDashboard. Responds 404 (not 403) so the route's existence
  is not revealed to non-admins.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    admin_email = Application.get_env(:mehungry, :admin_email)

    case conn.assigns[:current_user] do
      %{email: email} when email == admin_email and is_binary(admin_email) ->
        conn

      _ ->
        conn
        |> send_resp(:not_found, "Not Found")
        |> halt()
    end
  end
end
