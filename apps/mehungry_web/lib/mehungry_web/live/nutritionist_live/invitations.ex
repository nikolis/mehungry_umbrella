defmodule MehungryWeb.NutritionistLive.Invitations do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    invitations = Professionals.list_sent_invitations(user.id)

    socket =
      socket
      |> assign(:invitations, invitations)
      |> assign(:page_title, "Invitations")
      |> assign(:invite_email, "")
      |> assign(:invite_message, "")
      |> assign(:invite_error, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("invite_client", %{"email" => email, "message" => message}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.invite_client(professional_id, String.trim(email), message) do
      {:ok, _invitation} ->
        invitations = Professionals.list_sent_invitations(professional_id)

        {:noreply,
         socket
         |> assign(:invitations, invitations)
         |> assign(:invite_email, "")
         |> assign(:invite_message, "")
         |> assign(:invite_error, nil)
         |> put_flash(:info, "Invitation sent to #{email}.")}

      {:error, :client_not_found} ->
        {:noreply, assign(socket, :invite_error, "No user found with that email address.")}

      {:error, :already_invited} ->
        {:noreply,
         assign(socket, :invite_error, "You already have a pending invitation to this user.")}

      {:error, :already_client} ->
        {:noreply, assign(socket, :invite_error, "This user is already your client.")}

      {:error, _} ->
        {:noreply, assign(socket, :invite_error, "Could not send invitation. Please try again.")}
    end
  end

  @impl true
  def handle_event("revoke_invitation", %{"id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.revoke_invitation(String.to_integer(id), professional_id) do
      {:ok, _} ->
        invitations = Professionals.list_sent_invitations(professional_id)

        {:noreply,
         socket |> assign(:invitations, invitations) |> put_flash(:info, "Invitation revoked.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revoke invitation.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">Invitations</h1>

      <!-- Invite form -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 mb-8">
        <h2 class="text-parchment font-display font-semibold mb-4">Invite a client</h2>
        <form phx-submit="invite_client" class="space-y-3">
          <div>
            <label class="block text-sm text-parchment-dim mb-1">Client email address</label>
            <input
              type="email"
              name="email"
              value={@invite_email}
              required
              placeholder="client@example.com"
              class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
            />
          </div>
          <div>
            <label class="block text-sm text-parchment-dim mb-1">Personal message (optional)</label>
            <textarea
              name="message"
              rows="2"
              placeholder="Hi! I'd like to be your nutrition coach..."
              class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
            >{@invite_message}</textarea>
          </div>
          <%= if @invite_error do %>
            <p class="text-red-400 text-sm">{@invite_error}</p>
          <% end %>
          <button type="submit" class="btn btn-sm bg-paprika hover:bg-paprika-soft text-ink border-0">
            Send Invitation
          </button>
        </form>
      </div>

      <!-- Sent invitations -->
      <h2 class="text-parchment font-display font-semibold mb-3">Sent Invitations</h2>

      <%= if Enum.empty?(@invitations) do %>
        <p class="text-parchment-dim text-sm">No invitations sent yet.</p>
      <% else %>
        <div class="space-y-3">
          <%= for inv <- @invitations do %>
            <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 flex items-center justify-between">
              <div>
                <p class="text-parchment text-sm font-medium">
                  {if inv.client && inv.client.name, do: inv.client.name, else: "Unknown"}
                </p>
                <div class="flex items-center gap-2 mt-1">
                  <span class={[
                    "text-xs px-2 py-0.5 rounded-full font-medium",
                    inv.status == "pending" && "bg-yellow-500/20 text-yellow-400",
                    inv.status == "accepted" && "bg-green-500/20 text-green-400",
                    inv.status == "declined" && "bg-red-500/20 text-red-400"
                  ]}>
                    {String.capitalize(inv.status)}
                  </span>
                  <span class="text-parchment-dim text-xs">
                    {Calendar.strftime(inv.inserted_at, "%b %d, %Y")}
                  </span>
                </div>
              </div>
              <%= if inv.status == "pending" do %>
                <button
                  phx-click="revoke_invitation"
                  phx-value-id={inv.id}
                  data-confirm="Revoke this invitation?"
                  class="text-xs text-red-400 hover:text-red-300"
                >
                  Revoke
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
