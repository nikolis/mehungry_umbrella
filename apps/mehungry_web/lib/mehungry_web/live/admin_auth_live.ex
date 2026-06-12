defmodule MehungryWeb.AdminAuthLive do
  import Phoenix.LiveView

  use MehungryWeb, :live_view

  alias Mehungry.Accounts

  @admin_email "nikolisgal@gmail.com"

  def on_mount(_, _params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        {:halt, redirect(socket, to: "/login")}

      user.email != @admin_email ->
        {:halt, redirect(socket, to: "/home")}

      true ->
        socket =
          assign_new(socket, :current_language, fn ->
            Accounts.get_user_language(user.id)
          end)

        {:cont, socket}
    end
  end
end
