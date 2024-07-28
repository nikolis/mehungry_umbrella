defmodule MehungryWeb.HomeLive.FormComponentComment do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Posts
  alias Mehungry.Posts.Comment

  @impl true
  def render(assigns) do
    ~H"""
    <div class="post_card">
      <.header>
      </.header>

      <.simple_form
        for={@form}
        id="comment-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="flex flex-row gap-3">
          <img src={@current_user.profile_pic}  style="border-radius: 50%; width: 40px; height: 40px;" />
          <.input field={@form[:text]} type="text" class="flex-grow w-full" label="Comment "/>
          <.input field={@form[:user_id]} type="hidden" />
          <.input field={@form[:post_id]} type="hidden"  />

        </div>
        <:actions>
        <div style="display: grid; grid-template-columns: 19fr 2fr 2fr; margin-top: 0.5rem;">
          <div> </div>
          <button phx-click="cancel_comment" style="margin-right: 1.5rem; color: var(--clr-grey-friend_3)" type="reset" phx-target = {@myself} > Cancel </button>
          <button type="submit" class="primary_button" phx-disable-with="Saving..." >Post</button>

        </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{comment: comment} = assigns, socket) do
    changeset = Posts.change_comment(comment)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"comment" => comment_params}, socket) do
    changeset =
      socket.assigns.comment
      |> Posts.change_comment(comment_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("cancel_comment", _, socket) do
    changeset = Posts.change_comment(socket.assigns.comment)

    socket =
      socket
      |> assign(:reply, nil)
      |> assign_form(changeset)

    {:noreply, socket}
  end

  def handle_event("save", %{"comment" => comment_params}, socket) do
    save_comment(socket, socket.assigns.action, comment_params)
  end

  defp save_comment(socket, :show, comment_params) do
    case Posts.create_comment(comment_params) do
      {:ok, comment} ->
        comment_params_clean = Map.put(comment_params, "text", "")
        notify_parent({:saved, comment})
        changeset_new = Posts.change_comment(%Comment{}, comment_params_clean)

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

  defp save_comment(socket, :new, comment_params) do
    case Posts.create_comment(comment_params) do
      {:ok, comment} ->
        notify_parent({:saved, comment})

        {:noreply,
         socket
         |> put_flash(:info, "Comment created successfully")
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
