defmodule MehungryWeb.UserAuthLive do
  import Phoenix.LiveView

  use MehungryWeb, :live_view

  alias Mehungry.Accounts

  def on_mount(_, _params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/users/log_in")}
    end
  end

  def on_mount(_, _params, %{}, socket) do
    {:halt, redirect(socket, to: "/users/log_in")}
  end
end
