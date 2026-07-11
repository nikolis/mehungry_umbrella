defmodule MehungryWeb.AdminAuthLive do
  import Phoenix.LiveView

  use MehungryWeb, :live_view

  alias Mehungry.{Accounts, AiBot}

  def on_mount(_, _params, %{"user_token" => user_token}, socket) do
    socket =
      assign_new(socket, :current_user, fn ->
        Accounts.get_user_by_session_token(user_token)
      end)

    user = socket.assigns.current_user

    cond do
      is_nil(user) ->
        {:halt, redirect(socket, to: "/login")}

      user.email != Application.get_env(:mehungry, :admin_email) ->
        {:halt, redirect(socket, to: "/home")}

      true ->
        socket =
          socket
          |> assign_new(:current_language, fn -> Accounts.get_user_language(user.id) end)
          |> assign(:pending_bot_reviews, AiBot.count_pending_reviews())

        {:cont, socket}
    end
  end

  # Session reached the socket without a user_token (e.g. a returning session or
  # remember-me auth that did not carry the token into the LiveView session).
  # Match the sibling auth modules and redirect to login instead of raising a
  # FunctionClauseError.
  def on_mount(_, _params, %{}, socket) do
    {:halt, redirect(socket, to: "/login")}
  end
end
