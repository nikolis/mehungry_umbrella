defmodule MehungryWeb.CommentAnswerLive.Show do
  use MehungryWeb, :live_view
  import MehungryWeb.CoreComponents

  alias Mehungry.Posts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:comment_answer, Posts.get_comment_answer!(id))}
  end

  defp page_title(:show), do: "Show Comment answer"
  defp page_title(:edit), do: "Edit Comment answer"
end
