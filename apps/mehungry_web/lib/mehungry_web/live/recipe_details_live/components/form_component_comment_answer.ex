defmodule MehungryWeb.RecipeDetailsLive.FormComponentCommentAnswer do
  use MehungryWeb, :live_component
  import MehungryWeb.CoreComponents

  alias Mehungry.Posts
  alias Mehungry.Posts.CommentAnswer

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-8/12 sm:w-10/12" id="comment_answer_form" phx-hook={SelectComponentList}>

      <.header></.header>
      <%= if !is_nil(@must_be_loged_in) do %>
        <.modal
          id="browse_index_must_be_login"
          show
          on_cancel={JS.push("keep_browsing")}
          class="h-full"
          %
        >
          <.live_component module={MehungryWeb.MustBeLoginComponent} id={:new} patch={~p"/browse"} />
        </.modal>
      <% end %>

      <.simple_form
        for={@form}
        id={assigns.id}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="flex flex-row gap-4">
          <%= if !is_nil(@user) and @user.profile_pic do %>
            <img src={@user.profile_pic} , style="width: 30px; height: 30px; border-radius: 50%;" />
          <% else %>
            <.icon name="hero-user-circle" class="h-10 w-10" />
          <% end %>

          <.input field={@form[:text]} type="text" label="Reply" style="margin: 0px; " />
          <.input field={@form[:user_id]} type="hidden" />
          <.input field={@form[:comment_id]} type="hidden" />
        </div>
        <:actions>
          <div style="display: grid; grid-template-columns: 19fr 2fr 2fr; margin-top: 0.5rem;">
            <div></div>
            <button
              phx-click="cancel_comment_reply"
              type="button"
              style="margin-right: 1.5rem; color: var(--clr-grey-friend_3)"
            >
              Cancel
            </button>
            <button class="primary_button" phx-disable-with="Saving...">Post</button>
          </div>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{comment_answer: comment_answer} = assigns, socket) do
    changeset = Posts.change_comment_answer(%CommentAnswer{}, comment_answer)

    {:ok,
     socket
     |> assign(:must_be_loged_in, nil)
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("keep_browsing", _thing, socket) do
    {:noreply, assign(socket, :must_be_loged_in, nil)}
  end
  
  @impl true
  def handle_event("cancel_comment_reply", _, socket) do
    socket =
      socket
      |> assign(:reply, nil)
  
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"comment_answer" => comment_answer_params}, socket) do
    changeset =
      %CommentAnswer{}
      |> Posts.change_comment_answer(comment_answer_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"comment_answer" => comment_answer_params}, socket) do
    case is_nil(socket.assigns.user) do
      true ->
        socket = assign(socket, :must_be_loged_in, 1)
        {:noreply, socket}

      false ->
        save_comment_answer(socket, socket.assigns.action, comment_answer_params)
    end
  end

  defp save_comment_answer(socket, _, comment_answer_params) do
    case Posts.create_comment_answer(comment_answer_params) do
      {:ok, _comment_answer} ->
        comment_answer_params_clean = Map.put(comment_answer_params, "text", "")
        # notify_parent({:saved, comment_answer})
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

  # defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
