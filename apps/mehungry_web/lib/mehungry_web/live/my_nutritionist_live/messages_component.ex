defmodule MehungryWeb.MyNutritionistLive.MessagesComponent do
  @moduledoc """
  The client side of the client↔nutritionist conversation, embedded in the
  "My nutritionist" hub (`MyNutritionistLive.Index`). A client has at most one
  nutritionist (`TutorClientAssignment`), so this is a single thread.

  Messaging has **no standalone page or menu entry** — it is only meaningful
  between a nutritionist and their one connected client, so it lives here as a
  component rather than a top-level route.

  The parent LiveView owns the PubSub subscription (LiveComponents can't receive
  `handle_info`) and forwards each incoming message via
  `send_update(__MODULE__, id: ..., new_message: msg)`. Everything else — loading
  the thread, marking it read on open, and sending — lives here.
  """
  use MehungryWeb, :live_component

  alias Mehungry.Professionals

  # ── Update ───────────────────────────────────────────────────────────────────
  @impl true
  def update(%{new_message: message}, socket) do
    # A message pushed in by the parent's PubSub handler. Having the thread open
    # reads it immediately.
    client_id = socket.assigns.current_user.id
    Professionals.mark_thread_read(message.professional_id, client_id, client_id)
    {:ok, assign(socket, :messages, append_message(socket.assigns.messages, message))}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:message_body, fn -> "" end)
      |> load_thread_once()

    {:ok, socket}
  end

  # Load (and mark read) only on the first update; later parent re-renders must
  # not clobber the thread or re-run the read side effect.
  defp load_thread_once(socket) do
    if Map.has_key?(socket.assigns, :messages) do
      socket
    else
      %{assignment: assignment, current_user: %{id: client_id}} = socket.assigns
      Professionals.mark_thread_read(assignment.professional_id, client_id, client_id)
      assign(socket, :messages, Professionals.list_messages(assignment.professional_id, client_id))
    end
  end

  # ── Events ───────────────────────────────────────────────────────────────────
  @impl true
  def handle_event("send_message", %{"body" => body}, socket) do
    %{assignment: assignment, current_user: %{id: client_id}} = socket.assigns

    case Professionals.send_message(assignment.professional_id, client_id, client_id, body) do
      {:ok, message} ->
        {:noreply,
         socket
         |> assign(:messages, append_message(socket.assigns.messages, message))
         |> assign(:message_body, "")}

      {:error, _changeset} ->
        # Components can't `put_flash`; let the host LiveView surface it.
        send(self(), {:put_flash, :error, gettext("Message can't be empty.")})
        {:noreply, socket}
    end
  end

  # Append unless already present (the sender appends optimistically and also
  # receives its own broadcast echo forwarded by the parent).
  defp append_message(messages, message) do
    if Enum.any?(messages, &(&1.id == message.id)), do: messages, else: messages ++ [message]
  end

  # ── Render ───────────────────────────────────────────────────────────────────
  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
      <% professional = @assignment.professional %>
      <div class="flex items-center gap-3 mb-4">
        <%= if professional.profile_pic do %>
          <img src={professional.profile_pic} class="w-10 h-10 rounded-full object-cover" />
        <% else %>
          <div class="w-10 h-10 rounded-full bg-basil flex items-center justify-center text-ink font-bold text-sm">
            {String.first(professional.name || "?")}
          </div>
        <% end %>
        <div>
          <p class="text-parchment-dim text-xs">{gettext("Your nutritionist")}</p>
          <p class="text-parchment font-medium">{professional.name || professional.email}</p>
        </div>
      </div>

      <.message_thread
        messages={@messages}
        current_user_id={@current_user.id}
        body={@message_body}
        target={@myself}
        placeholder={gettext("Message your nutritionist…")}
      />
    </div>
    """
  end
end
