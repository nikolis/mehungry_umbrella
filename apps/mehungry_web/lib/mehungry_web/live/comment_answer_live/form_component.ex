defmodule MehungryWeb.CommentAnswerLive.FormComponent do
  use MehungryWeb, :live_component
  alias Mehungry.Posts
  import MehungryWeb.CoreComponents

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        <%= @title %>
        <:subtitle>Use this form to manage comment_answer records in your database.</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="comment_answer-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:text]} type="text" label="Text" />
        <:actions>
          <.button phx-disable-with="Saving...">Save Comment answer</.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{comment_answer: comment_answer} = assigns, socket) do
    changeset = Posts.change_comment_answer(comment_answer)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"comment_answer" => comment_answer_params}, socket) do
    changeset =
      socket.assigns.comment_answer
      |> Posts.change_comment_answer(comment_answer_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"comment_answer" => comment_answer_params}, socket) do
    save_comment_answer(socket, socket.assigns.action, comment_answer_params)
  end

  defp save_comment_answer(socket, :edit, comment_answer_params) do
    case Posts.update_comment_answer(socket.assigns.comment_answer, comment_answer_params) do
      {:ok, comment_answer} ->
        notify_parent({:saved, comment_answer})

        {:noreply,
         socket
         |> put_flash(:info, "Comment answer updated successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_comment_answer(socket, :new, comment_answer_params) do
    case Posts.create_comment_answer(comment_answer_params) do
      {:ok, comment_answer} ->
        notify_parent({:saved, comment_answer})

        {:noreply,
         socket
         |> put_flash(:info, "Comment answer created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
