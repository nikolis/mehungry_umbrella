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
      |> assign(:search_query, "")
      |> assign(:search_results, [])

    {:ok, socket}
  end

  @impl true
  def handle_event("search_users", %{"query" => query}, socket) do
    professional_id = socket.assigns.current_user.id
    results = Professionals.search_invitable_users(professional_id, query)

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)}
  end

  @impl true
  def handle_event("invite_user", %{"id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.invite_client_by_id(professional_id, String.to_integer(id)) do
      {:ok, _invitation} ->
        results = Professionals.search_invitable_users(professional_id, socket.assigns.search_query)

        {:noreply,
         socket
         |> refresh_invitations(professional_id)
         |> assign(:search_results, results)
         |> put_flash(:info, "Invitation sent.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, invite_error_message(reason))}
    end
  end

  @impl true
  def handle_event("invite_client", %{"email" => email, "message" => message}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.invite_client(professional_id, String.trim(email), message) do
      {:ok, _invitation} ->
        {:noreply,
         socket
         |> refresh_invitations(professional_id)
         |> assign(:invite_email, "")
         |> assign(:invite_message, "")
         |> assign(:invite_error, nil)
         |> put_flash(:info, "Invitation sent to #{email}.")}

      {:error, reason} ->
        {:noreply, assign(socket, :invite_error, invite_error_message(reason))}
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

  defp refresh_invitations(socket, professional_id) do
    assign(socket, :invitations, Professionals.list_sent_invitations(professional_id))
  end

  defp invite_error_message(:client_not_found), do: "No user found with that email address."

  defp invite_error_message(:already_invited),
    do: "You already have a pending invitation to this user."

  defp invite_error_message(:already_client), do: "This user is already your client."
  defp invite_error_message(:self_invite), do: "You can't invite yourself."
  defp invite_error_message(_), do: "Could not send invitation. Please try again."

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">Invitations</h1>

      <!-- Invite form -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-6 mb-8">
        <h2 class="text-parchment font-display font-semibold mb-4">Invite a client</h2>

        <!-- Search existing users -->
        <div>
          <label class="block text-sm text-parchment-dim mb-1">Search by name</label>
          <form id="user-search-form" phx-change="search_users" phx-submit="search_users">
            <input
              type="text"
              name="query"
              value={@search_query}
              phx-debounce="250"
              autocomplete="off"
              placeholder="Search m3hungry users by name…"
              class="w-full bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm focus:outline-none focus:border-paprika"
            />
          </form>
          <p class="text-parchment-dim text-xs mt-1">
            Find users who signed in with Facebook or Google even if you don't know their email.
          </p>

          <%= cond do %>
            <% String.trim(@search_query) == "" -> %>
            <% @search_results == [] -> %>
              <p class="text-parchment-dim text-sm mt-3">No matching users found.</p>
            <% true -> %>
              <ul class="mt-3 space-y-2">
                <%= for %{user: user, status: status} <- @search_results do %>
                  <li class="flex items-center justify-between gap-3 bg-ink-panel2 rounded-lg px-3 py-2">
                    <div class="flex items-center gap-3 min-w-0">
                      <%= if user.profile_pic do %>
                        <img src={user.profile_pic} alt="" class="w-8 h-8 rounded-full object-cover flex-shrink-0" />
                      <% else %>
                        <div class="w-8 h-8 rounded-full bg-ink-panel flex-shrink-0 flex items-center justify-center text-parchment-dim text-xs">
                          {String.first(user.name || "?")}
                        </div>
                      <% end %>
                      <div class="min-w-0">
                        <p class="text-parchment text-sm font-medium truncate">
                          {user.name || "Unknown"}
                        </p>
                        <%= if user.user_profile && user.user_profile.alias && user.user_profile.alias != user.name do %>
                          <p class="text-parchment-dim text-xs truncate">{user.user_profile.alias}</p>
                        <% end %>
                      </div>
                    </div>
                    <%= case status do %>
                      <% :invitable -> %>
                        <.action
                          variant={:secondary}
                          size={:sm}
                          type="button"
                          phx-click="invite_user"
                          phx-value-id={user.id}
                        >
                          Invite
                        </.action>
                      <% :invited -> %>
                        <span class="text-xs text-yellow-400 flex-shrink-0">Invited</span>
                      <% :client -> %>
                        <span class="text-xs text-green-400 flex-shrink-0">Client</span>
                    <% end %>
                  </li>
                <% end %>
              </ul>
          <% end %>
        </div>

        <div class="flex items-center gap-3 my-5">
          <div class="flex-1 h-px bg-ink-panel2"></div>
          <span class="text-parchment-dim text-xs uppercase tracking-wide">or invite by email</span>
          <div class="flex-1 h-px bg-ink-panel2"></div>
        </div>

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
          <.action variant={:primary} size={:sm} type="submit">Send invitation</.action>
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
