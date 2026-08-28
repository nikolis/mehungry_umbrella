defmodule MehungryWeb.NutritionistLive.UserInvitations do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    client_id = socket.assigns.current_user.id
    invitations = Professionals.list_pending_invitations_for_client(client_id)
    active_assignment = Professionals.get_assignment_for_client(client_id)

    socket =
      socket
      |> assign(:invitations, invitations)
      |> assign(:active_assignment, active_assignment)
      |> assign(:page_title, "Tutor Invitations")

    {:ok, socket}
  end

  @impl true
  def handle_event("accept_invitation", %{"id" => id}, socket) do
    client_id = socket.assigns.current_user.id

    case Professionals.accept_invitation(String.to_integer(id), client_id) do
      {:ok, _assignment} ->
        invitations = Professionals.list_pending_invitations_for_client(client_id)
        active_assignment = Professionals.get_assignment_for_client(client_id)

        {:noreply,
         socket
         |> assign(:invitations, invitations)
         |> assign(:active_assignment, active_assignment)
         |> put_flash(:info, "You now have a nutritionist!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not accept invitation.")}
    end
  end

  @impl true
  def handle_event("decline_invitation", %{"id" => id}, socket) do
    client_id = socket.assigns.current_user.id

    case Professionals.decline_invitation(String.to_integer(id), client_id) do
      {:ok, _} ->
        invitations = Professionals.list_pending_invitations_for_client(client_id)

        {:noreply,
         socket |> assign(:invitations, invitations) |> put_flash(:info, "Invitation declined.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not decline invitation.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">Tutor Invitations</h1>

      <!-- Active nutritionist banner -->
      <%= if @active_assignment do %>
        <% professional = @active_assignment.professional %>
        <div class="bg-basil/10 border border-basil/30 rounded-xl p-5 mb-6">
          <p class="text-basil text-sm font-medium mb-2">Your current nutritionist</p>
          <div class="flex items-center gap-3">
            <%= if professional.profile_pic do %>
              <img src={professional.profile_pic} class="w-10 h-10 rounded-full object-cover" />
            <% else %>
              <div class="w-10 h-10 rounded-full bg-basil flex items-center justify-center text-ink font-bold text-sm">
                {String.first(professional.name || "?")}
              </div>
            <% end %>
            <p class="text-parchment font-medium">{professional.name || professional.email}</p>
          </div>
        </div>
      <% end %>

      <!-- Pending invitations -->
      <%= if Enum.empty?(@invitations) do %>
        <div class="text-center py-16">
          <p class="text-parchment-dim">No pending invitations.</p>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for inv <- @invitations do %>
            <% professional = inv.professional %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
              <div class="flex items-start gap-3 mb-4">
                <%= if professional.profile_pic do %>
                  <img
                    src={professional.profile_pic}
                    class="w-10 h-10 rounded-full object-cover shrink-0"
                  />
                <% else %>
                  <div class="w-10 h-10 rounded-full bg-ink-panel2 flex items-center justify-center text-parchment font-bold text-sm shrink-0">
                    {String.first(professional.name || "?")}
                  </div>
                <% end %>
                <div class="flex-1">
                  <p class="text-parchment font-medium">{professional.name || professional.email}</p>
                  <%= if inv.message do %>
                    <p class="text-parchment-dim text-sm mt-2 bg-ink/50 rounded-lg px-3 py-2 italic">
                      "{inv.message}"
                    </p>
                  <% end %>
                </div>
              </div>
              <div class="flex gap-3">
                <button
                  phx-click="accept_invitation"
                  phx-value-id={inv.id}
                  class="flex-1 py-2 rounded-lg bg-paprika hover:bg-paprika-soft text-ink text-sm font-medium transition"
                >
                  Accept
                </button>
                <button
                  phx-click="decline_invitation"
                  phx-value-id={inv.id}
                  class="flex-1 py-2 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment-dim text-sm font-medium transition"
                >
                  Decline
                </button>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
