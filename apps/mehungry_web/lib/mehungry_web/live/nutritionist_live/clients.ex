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
      <div class="flex items-center justify-between mb-6">
        <h1 class="text-2xl font-bold text-white">My Clients</h1>
        <a
          href="/nutritionist/invitations"
          class="btn btn-sm bg-teal-600 hover:bg-teal-500 text-white border-0"
        >
          + Invite Client
        </a>
      </div>

      <%= if Enum.empty?(@clients) do %>
        <div class="text-center py-16">
          <p class="text-slate-400 mb-4">No clients yet.</p>
          <a href="/nutritionist/invitations" class="text-teal-400 hover:underline text-sm">Send your first invitation →</a>
        </div>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%= for assignment <- @clients do %>
            <% client = assignment.client %>
            <div class="bg-slate-800 border border-slate-700 rounded-xl p-4">
              <div class="flex items-center gap-3 mb-3">
                <%= if client.profile_pic do %>
                  <img src={client.profile_pic} class="w-10 h-10 rounded-full object-cover" />
                <% else %>
                  <div class="w-10 h-10 rounded-full bg-teal-600 flex items-center justify-center text-white font-bold text-sm">
                    {String.first(client.name || "?")}
                  </div>
                <% end %>
                <div>
                  <p class="text-white font-medium text-sm">{client.name || client.email}</p>
                  <p class="text-slate-500 text-xs">
                    Client since {Calendar.strftime(assignment.inserted_at, "%b %Y")}
                  </p>
                </div>
              </div>

              <div class="flex gap-2">
                <a
                  href={"/nutritionist/clients/#{client.id}"}
                  class="flex-1 text-center text-xs py-1.5 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 transition"
                >
                  Overview
                </a>
                <a
                  href={"/nutritionist/clients/#{client.id}/calendar"}
                  class="flex-1 text-center text-xs py-1.5 rounded-lg bg-teal-700 hover:bg-teal-600 text-white transition"
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
                    class="text-xs py-1.5 px-3 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 transition"
                  >
                    Cancel
                  </button>
                <% else %>
                  <button
                    phx-click="confirm_remove"
                    phx-value-client-id={client.id}
                    class="text-xs py-1.5 px-2 rounded-lg bg-slate-700 hover:bg-red-900 text-slate-400 hover:text-red-400 transition"
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
