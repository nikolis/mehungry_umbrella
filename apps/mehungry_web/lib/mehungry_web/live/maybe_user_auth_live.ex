defmodule MehungryWeb.MaybeUserAuthLive do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts

  def on_mount(_, _params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    socket =
      assign_new(socket, :current_language, fn ->
        case socket.assigns[:current_user] do
          nil -> "en"
          user -> Accounts.get_user_language(user.id)
        end
      end)

    {:cont, socket}
  end

  def on_mount(_, _params, %{}, socket) do
    {:cont, assign_new(socket, :current_language, fn -> "en" end)}
  end
end
