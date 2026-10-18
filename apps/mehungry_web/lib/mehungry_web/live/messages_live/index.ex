defmodule MehungryWeb.MessagesLive.Index do
  @moduledoc """
  The client side of the client↔nutritionist conversation. A client has at most
  one nutritionist (`TutorClientAssignment`), so this is a single thread. Shows
  an empty state when the client has no nutritionist yet.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    client_id = socket.assigns.current_user.id
    assignment = Professionals.get_assignment_for_client(client_id)

    socket =
      socket
      |> assign(:page_title, "Messages")
      |> assign(:assignment, assignment)
      |> assign(:message_body, "")
      |> load_thread(assignment, client_id, connected?(socket))

    {:ok, socket}
  end

  defp load_thread(socket, nil, _client_id, _connected?), do: assign(socket, :messages, [])

  defp load_thread(socket, assignment, client_id, connected?) do
    professional_id = assignment.professional_id

    if connected? do
      Professionals.subscribe_to_messages(client_id)
    end

    # Opening the thread reads the nutritionist's messages.
    Professionals.mark_thread_read(professional_id, client_id, client_id)

    assign(socket, :messages, Professionals.list_messages(professional_id, client_id))
  end

  @impl true
  def handle_event("send_message", %{"body" => body}, socket) do
    case socket.assigns.assignment do
      nil ->
        {:noreply, socket}

      assignment ->
        client_id = socket.assigns.current_user.id

        case Professionals.send_message(assignment.professional_id, client_id, client_id, body) do
          {:ok, message} ->
            {:noreply,
             socket
             |> assign(:messages, append_message(socket.assigns.messages, message))
             |> assign(:message_body, "")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Message can't be empty.")}
        end
    end
  end

  @impl true
  def handle_info({:assignment_message, message}, socket) do
    client_id = socket.assigns.current_user.id

    if message.client_id == client_id do
      Professionals.mark_thread_read(message.professional_id, client_id, client_id)
      {:noreply, assign(socket, :messages, append_message(socket.assigns.messages, message))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # Append unless already present (the sender appends optimistically and also
  # receives its own broadcast echo).
  defp append_message(messages, message) do
    if Enum.any?(messages, &(&1.id == message.id)), do: messages, else: messages ++ [message]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">Messages</h1>

      <%= if @assignment do %>
        <% professional = @assignment.professional %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <div class="flex items-center gap-3 mb-4">
            <%= if professional.profile_pic do %>
              <img src={professional.profile_pic} class="w-10 h-10 rounded-full object-cover" />
            <% else %>
              <div class="w-10 h-10 rounded-full bg-basil flex items-center justify-center text-ink font-bold text-sm">
                {String.first(professional.name || "?")}
              </div>
            <% end %>
            <div>
              <p class="text-parchment-dim text-xs">Your nutritionist</p>
              <p class="text-parchment font-medium">{professional.name || professional.email}</p>
            </div>
          </div>

          <.message_thread
            messages={@messages}
            current_user_id={@current_user.id}
            body={@message_body}
            placeholder="Message your nutritionist…"
          />
        </div>
      <% else %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl text-center py-16 px-4">
          <p class="text-parchment font-medium mb-1">You don't have a nutritionist yet</p>
          <p class="text-parchment-dim text-sm">
            Once you connect with a nutritionist, you can message them here.
          </p>
        </div>
      <% end %>
    </div>
    """
  end
end
