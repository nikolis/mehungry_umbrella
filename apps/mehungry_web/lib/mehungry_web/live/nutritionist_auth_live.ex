defmodule MehungryWeb.NutritionistAuthLive do
  import Phoenix.LiveView

  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Subscriptions

  def on_mount(_, _params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    case socket.assigns.current_user do
      nil ->
        {:halt, redirect(socket, to: "/users/log_in")}

      user ->
        if Subscriptions.nutritionist?(user.id) do
          socket =
            assign_new(socket, :current_language, fn ->
              Accounts.get_user_language(user.id)
            end)

          {:cont, socket}
        else
          {:halt,
           socket
           |> Phoenix.LiveView.put_flash(:error, "Professional subscription required.")
           |> redirect(to: "/home")}
        end
    end
  end

  def on_mount(_, _params, %{}, socket) do
    {:halt, redirect(socket, to: "/users/log_in")}
  end
end
