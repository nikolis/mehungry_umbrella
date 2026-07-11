defmodule MehungryWeb.UserAuthLive do
  import Phoenix.LiveView

  use MehungryWeb, :live_view

  alias Mehungry.Accounts

  def on_mount(_, _params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    cond do
      is_nil(socket.assigns.current_user) ->
        {:halt, redirect(socket, to: "/users/log_in")}

      is_nil(socket.assigns.current_user.confirmed_at) ->
        {:halt,
         socket
         |> put_flash(:error, "Please confirm your email address to continue.")
         |> redirect(to: "/users/log_in")}

      true ->
        socket =
          assign_new(socket, :current_language, fn ->
            Accounts.get_user_language(socket.assigns.current_user.id)
          end)

        {:cont, socket}
    end
  end

  def on_mount(_, _params, %{}, socket) do
    {:halt, redirect(socket, to: "/users/log_in")}
  end
end
