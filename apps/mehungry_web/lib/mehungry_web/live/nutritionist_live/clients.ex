defmodule MehungryWeb.NutritionistLive.Clients do
  use MehungryWeb, :live_view

  alias Mehungry.Accounts
  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    socket =
      socket
      |> assign(:page_title, "My Clients")
      |> assign(:confirm_remove_id, nil)
      |> assign(:show_new_form, false)
      |> assign(:new_alias, "")
      |> assign(:claim_link, nil)
      |> load_clients(user.id)

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
        {:noreply,
         socket
         |> assign(:confirm_remove_id, nil)
         |> load_clients(professional_id)
         |> put_flash(:info, "Client removed.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not remove client.")}
    end
  end

  @impl true
  def handle_event("new_client", _params, socket) do
    {:noreply, socket |> assign(:show_new_form, true) |> assign(:claim_link, nil)}
  end

  @impl true
  def handle_event("cancel_new", _params, socket) do
    {:noreply, assign(socket, :show_new_form, false)}
  end

  @impl true
  def handle_event("create_client", %{"alias" => alias_name}, socket) do
    professional_id = socket.assigns.current_user.id

    case alias_name |> to_string() |> String.trim() do
      "" ->
        {:noreply, put_flash(socket, :error, "Please enter a name for the client.")}

      trimmed ->
        case Professionals.create_managed_client(professional_id, trimmed) do
          {:ok, %{claim_token: token}} ->
            {:noreply,
             socket
             |> assign(:show_new_form, false)
             |> assign(:new_alias, "")
             |> assign(:claim_link, claim_url(token))
             |> load_clients(professional_id)
             |> put_flash(:info, "Client created. Share the claim link below so they can log in.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Could not create the client. Please try again.")}
        end
    end
  end

  @impl true
  def handle_event("regenerate_link", %{"client-id" => id}, socket) do
    professional_id = socket.assigns.current_user.id

    case Professionals.regenerate_claim_token(professional_id, String.to_integer(id)) do
      {:ok, token} ->
        {:noreply,
         socket
         |> assign(:claim_link, claim_url(token))
         |> put_flash(:info, "New claim link generated. The previous link no longer works.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not generate a claim link for this client.")}
    end
  end

  @impl true
  def handle_event("dismiss_link", _params, socket) do
    {:noreply, assign(socket, :claim_link, nil)}
  end

  defp load_clients(socket, professional_id) do
    assign(socket, :clients, Professionals.list_clients(professional_id))
  end

  defp claim_url(token), do: MehungryWeb.Endpoint.url() <> "/claim/" <> token

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <.page_header title="My Clients">
        <:actions>
          <.action variant={:secondary} size={:sm} phx-click="new_client">
            Create client
          </.action>
          <.action variant={:primary} size={:sm} navigate={~p"/nutritionist/invitations"}>
            Invite client
          </.action>
        </:actions>
      </.page_header>

      <%= if @show_new_form do %>
        <.panel_card class="mb-4">
          <form phx-submit="create_client" class="flex flex-col sm:flex-row gap-3 sm:items-end">
            <div class="flex-1">
              <label class="block text-sm text-parchment-dim mb-1">Client name (alias)</label>
              <input
                type="text"
                name="alias"
                value={@new_alias}
                autofocus
                placeholder="e.g. Maria K."
                class="w-full rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment px-3 py-2.5 focus:border-paprika focus:outline-none"
              />
              <p class="text-parchment-dim text-xs mt-1">
                Creates a login-less account you can plan for right away. Share the claim link
                to let them log in later — all their data carries over.
              </p>
            </div>
            <div class="flex gap-2">
              <button
                type="submit"
                class="text-sm py-2.5 px-4 rounded-lg bg-paprika hover:bg-paprika-soft text-ink font-bold transition"
              >
                Create
              </button>
              <button
                type="button"
                phx-click="cancel_new"
                class="text-sm py-2.5 px-4 rounded-lg bg-ink-panel2 hover:bg-ink text-parchment-dim transition"
              >
                Cancel
              </button>
            </div>
          </form>
        </.panel_card>
      <% end %>

      <%= if @claim_link do %>
        <.panel_card class="mb-4 border-paprika/40">
          <div class="flex items-start justify-between gap-3 mb-2">
            <p class="text-parchment text-sm font-medium">Claim link</p>
            <button
              phx-click="dismiss_link"
              class="text-parchment-dim hover:text-parchment text-xs"
              title="Dismiss"
            >
              ✕
            </button>
          </div>
          <p class="text-parchment-dim text-xs mb-3">
            Send this to your client. When they open it they set their own email and password
            and take over the account — keeping the calendar and meal plans you built.
          </p>
          <div class="flex gap-2">
            <input
              type="text"
              readonly
              value={@claim_link}
              onclick="this.select()"
              class="flex-1 rounded-lg bg-ink-panel2 border border-ink-panel2 text-parchment px-3 py-2 text-sm"
            />
            <button
              type="button"
              onclick={"navigator.clipboard.writeText('#{@claim_link}')"}
              class="text-sm py-2 px-4 rounded-lg bg-ink-panel2 hover:bg-ink border border-ink-panel2 text-parchment transition"
            >
              Copy
            </button>
          </div>
        </.panel_card>
      <% end %>

      <%= if Enum.empty?(@clients) do %>
        <.panel_card class="text-center py-16">
          <p class="text-parchment font-medium mb-1">No clients yet</p>
          <p class="text-parchment-dim text-sm mb-5">
            Create a client to start planning, or invite an existing m3hungry user to connect.
          </p>
          <.action variant={:primary} size={:sm} phx-click="new_client">
            Create your first client
          </.action>
        </.panel_card>
      <% else %>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <%= for assignment <- @clients do %>
            <% client = assignment.client %>
            <% unclaimed = Accounts.managed_unclaimed?(client) %>
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
                  <div class="flex items-center gap-2">
                    <p class="text-parchment font-medium text-sm">{client.name || client.email}</p>
                    <%= if unclaimed do %>
                      <span class="text-[10px] uppercase tracking-wide px-1.5 py-0.5 rounded bg-paprika/20 text-paprika-soft">
                        Pending claim
                      </span>
                    <% end %>
                  </div>
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
                  class="flex-1 inline-flex items-center justify-center gap-1.5 text-xs py-1.5 rounded-lg bg-paprika hover:bg-paprika-soft text-ink transition"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="2"
                    stroke="currentColor"
                    class="size-3.5 flex-shrink-0"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 0 1 2.25-2.25h13.5A2.25 2.25 0 0 1 21 7.5v11.25m-18 0A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75m-18 0v-7.5A2.25 2.25 0 0 1 5.25 9h13.5A2.25 2.25 0 0 1 21 11.25v7.5"
                    />
                  </svg>
                  View Plan
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

              <%= if unclaimed do %>
                <button
                  phx-click="regenerate_link"
                  phx-value-client-id={client.id}
                  class="mt-2 w-full text-center text-xs py-1.5 rounded-lg bg-ink-panel2 hover:bg-ink border border-ink-panel2 text-parchment-dim hover:text-parchment transition"
                >
                  Get claim link
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
