defmodule MehungryWeb.RecipeChannel do
  @moduledoc """
  Live comments/likes on an open recipe (spec §13 `recipe:<id>`). Public to join.
  Pushes `"comment_created"` and `"like_changed"`; accepts `"new_comment"` from
  authenticated sockets and broadcasts the created comment to the topic.
  """
  use MehungryWeb, :channel

  alias Mehungry.Posts

  @impl true
  def join("recipe:" <> _id, _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("new_comment", %{"text" => text}, socket) do
    case socket.assigns[:user_id] do
      nil ->
        {:reply, {:error, %{reason: "unauthorized"}}, socket}

      user_id ->
        "recipe:" <> recipe_id = socket.topic

        attrs = %{"text" => text, "recipe_id" => String.to_integer(recipe_id), "user_id" => user_id}

        case Posts.create_comment(attrs) do
          {:ok, comment} ->
            payload = %{id: comment.id, text: comment.text, user_id: user_id}
            broadcast!(socket, "comment_created", %{comment: payload})
            {:reply, {:ok, payload}, socket}

          {:error, _changeset} ->
            {:reply, {:error, %{reason: "invalid"}}, socket}
        end
    end
  end
end
