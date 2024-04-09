defmodule MehungryWeb.CommentAnswerLive.Index do
  use MehungryWeb, :live_view

  import MehungryWeb.CoreComponents

  alias Mehungry.Posts
  alias Mehungry.Posts.CommentAnswer

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :comment_answers, Posts.list_comment_answers())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Comment answer")
    |> assign(:comment_answer, Posts.get_comment_answer!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Comment answer")
    |> assign(:comment_answer, %CommentAnswer{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Comment answers")
    |> assign(:comment_answer, nil)
  end

  @impl true
  def handle_info({MehungryWeb.CommentAnswerLive.FormComponent, {:saved, comment_answer}}, socket) do
    {:noreply, stream_insert(socket, :comment_answers, comment_answer)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    comment_answer = Posts.get_comment_answer!(id)
    {:ok, _} = Posts.delete_comment_answer(comment_answer)

    {:noreply, stream_delete(socket, :comment_answers, comment_answer)}
  end
end
