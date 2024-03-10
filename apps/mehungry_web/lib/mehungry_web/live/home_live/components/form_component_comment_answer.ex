defmodule MehungryWeb.HomeLive.FormComponentCommentAnswer do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Posts
  alias Mehungry.Posts.CommentAnswer

  @impl true
  def render(assigns) do
    ~H"""
    <div class="" style= "margin-top: 0.75rem">
      <.header>
      </.header>

      <.simple_form
        for={@form}
        id={assigns.id}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div style="display: grid; grid-template-columns: 1fr 19fr; gap: 0.75rem;">
          <img src="/images/food4.jpeg"  style="border-radius: 50%; width: 40px; height: 40px;" />
          <.input field={@form[:text]} type="full-text" label="Reply" style="margin: 0px; "/>
          <.input field={@form[:user_id]} type="hidden" />
          <.input field={@form[:comment_id]} type="hidden"  />

        </div>
        <:actions>
        <div style="display: grid; grid-template-columns: 19fr 2fr 2fr; margin-top: 0.5rem;">
          <div> </div>
          <button phx-click="cancel_comment_reply" style="margin-right: 1.5rem; color: var(--clr-grey-friend_3)"> Cancel </button>
          <button class="primary_button" phx-disable-with="Saving...">Post</button>


        </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{comment_answer: comment_answer} = assigns, socket) do
    IO.inspect(comment_answer, label: "Upadet")
    changeset = Posts.change_comment_answer(%CommentAnswer{}, comment_answer)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"comment_answer" => comment_answer_params}, socket) do
    IO.inspect(comment_answer_params, label: "validate")

    changeset =
      %CommentAnswer{}
      |> Posts.change_comment_answer(comment_answer_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"comment_answer" => comment_answer_params}, socket) do
    IO.inspect(comment_answer_params, label: "sto stigno lemono handle ")
    save_comment_answer(socket, socket.assigns.action, comment_answer_params)
  end

  defp save_comment_answer(socket, :show, comment_answer_params) do
    IO.inspect(comment_answer_params, label: "Save")

    case Posts.create_comment_answer(comment_answer_params) do
      {:ok, comment_answer} ->
        comment_answer_params_clean = Map.put(comment_answer_params, "text", "")
        notify_parent({:saved, comment_answer})
        changeset_new = Posts.change_comment_answer(%CommentAnswer{}, comment_answer_params_clean)

        {
          :noreply,
          socket
          |> put_flash(:info, "Comment updated successfully")
          |> assign_form(changeset_new)
          # |> push_patch(to: socket.assigns.patch)}
        }

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
