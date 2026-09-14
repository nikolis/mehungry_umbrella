defmodule MehungryWeb.NutritionistLive.Clients do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    clients = Professionals.list_clients(user.id)

    socket =
      socket
      |> assign(:clients, clients)
      |> assign(:page_title, "My Clients")
      |> assign(:confirm_remove_id, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("confirm_remove", %{"client-id" => id}, socket) do
    {:noreply, assign(socket, :confirm_remove_id, String.to_integer(id))}
  end

  @impl true
  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, :confirm_remove_id, nil)}
  end

  @impl true
  def handle_event("remove_client", %{"client-id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.remove_client(professional_id, String.to_integer(id)) do
      {:ok, _} ->
        clients = Professionals.list_clients(professional_id)

        {:noreply,
         socket
         |> assign(:clients, clients)
         |> assign(:confirm_remove_id, nil)
         |> put_flash(:info, "Client removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove client.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <.page_header title="My Clients">
        <:actions>
          <.action variant={:primary} size={:sm} navigate={~p"/nutritionist/invitations"}>
            Invite client
          </.action>
        </:actions>
      </.page_header>

      <%= if Enum.empty?(@clients) do %>
        <.panel_card class="text-center py-16">
          <p class="text-parchment font-medium mb-1">No clients yet</p>
          <p class="text-parchment-dim text-sm mb-5">
            Invite someone to connect and start planning together.
          </p>
          <.action variant={:primary} size={:sm} navigate={~p"/nutritionist/invitations"}>
            Send your first invitation
          </.action>
        </.panel_card>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%= for assignment <- @clients do %>
            <% client = assignment.client %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4">
              <div class="flex items-center gap-3 mb-3">
                <%= if client.profile_pic do %>
                  <img src={client.profile_pic} class="w-10 h-10 rounded-full object-cover" />
                <% else %>
                  <div class="w-10 h-10 rounded-full bg-basil flex items-center justify-center text-ink font-bold text-sm">
                    {String.first(client.name || "?")}
                  </div>
                <% end %>
                <div>
                  <p class="text-parchment font-medium text-sm">{client.name || client.email}</p>
                  <p class="text-parchment-dim text-xs">
                    Client since {Calendar.strftime(assignment.inserted_at, "%b %Y")}
                  </p>
                </div>
              </div>

              <div class="flex gap-2">
                <a
                  href={"/nutritionist/clients/#{client.id}"}
                  class="flex-1 text-center text-xs py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink border border-ink-panel2 text-parchment-dim hover:text-parchment transition"
                >
                  Overview
                </a>
                <a
                  href={"/nutritionist/clients/#{client.id}/calendar"}
                  class="flex-1 text-center text-xs py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink transition"
                >
                  Edit Meal Plan
                </a>
                <%= if @confirm_remove_id == client.id do %>
                  <button
                    phx-click="remove_client"
                    phx-value-client-id={client.id}
                    class="text-xs py-1.5 px-3 rounded-lg bg-red-700 hover:bg-red-600 text-white transition"
                  >
                    Confirm
                  </button>
                  <button
                    phx-click="cancel_remove"
                    class="text-xs py-1.5 px-3 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment-dim transition"
                  >
                    Cancel
                  </button>
                <% else %>
                  <button
                    phx-click="confirm_remove"
                    phx-value-client-id={client.id}
                    class="text-xs py-1.5 px-2 rounded-lg bg-ink-panel2 hover:bg-red-900/60 text-parchment-dim hover:text-red-400 transition"
                    title="Remove client"
                  >
                    ✕
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
