defmodule MehungryWeb.NutritionistLive.Dashboard do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    profile = Professionals.get_professional_profile(user.id)
    client_count = Professionals.count_clients(user.id)
    upcoming = Professionals.list_upcoming_appointments(user.id, 5)

    pending_sent =
      length(Enum.filter(Professionals.list_sent_invitations(user.id), &(&1.status == "pending")))

    socket =
      socket
      |> assign(:profile, profile)
      |> assign(:client_count, client_count)
      |> assign(:upcoming_appointments, upcoming)
      |> assign(:pending_invitations_sent, pending_sent)
      |> assign(:page_title, "Nutritionist Dashboard")

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <h1 class="text-2xl font-display font-bold text-parchment mb-6">Dashboard</h1>

      <%= if @profile do %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 mb-6 flex items-center justify-between">
          <div>
            <p class="text-parchment font-medium capitalize">
              {@profile.display_name || @profile.specialization}
            </p>
            <p class="text-parchment-dim text-sm mt-1">
              <%= if @profile.is_public do %>
                Public ·
                <a href={"/nutritionists/#{@profile.slug}"} class="text-paprika hover:text-paprika-soft">view page</a>
              <% else %>
                Not published yet
              <% end %>
            </p>
          </div>
          <a href="/nutritionist/profile" class="text-sm text-paprika hover:text-paprika-soft">Edit profile</a>
        </div>
      <% else %>
        <div class="bg-basil/10 border border-basil/30 rounded-xl p-4 mb-6 flex items-center justify-between">
          <p class="text-parchment text-sm">
            Complete your professional profile so clients can find and book you.
          </p>
          <a
            href="/nutritionist/profile"
            class="text-sm font-medium text-paprika hover:text-paprika-soft whitespace-nowrap"
          >Set up profile →</a>
        </div>
      <% end %>

      <!-- Stats -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Active Clients</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">{@client_count}</p>
          <a href="/nutritionist/clients" class="text-paprika hover:text-paprika-soft text-xs mt-2 block">View all →</a>
        </div>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Pending Invitations</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">{@pending_invitations_sent}</p>
          <a href="/nutritionist/invitations" class="text-paprika hover:text-paprika-soft text-xs mt-2 block">Manage →</a>
        </div>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Upcoming Appointments</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">{length(@upcoming_appointments)}</p>
          <a
            href="/nutritionist/appointments"
            class="text-paprika hover:text-paprika-soft text-xs mt-2 block"
          >Calendar →</a>
        </div>
      </div>

      <!-- Upcoming appointments -->
      <%= if length(@upcoming_appointments) > 0 do %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">Upcoming Appointments</h2>
          <div class="space-y-3">
            <%= for appt <- @upcoming_appointments do %>
              <div class="flex items-center justify-between py-2 border-b border-ink-panel2 last:border-0">
                <div>
                  <p class="text-parchment text-sm font-medium">{appt.title}</p>
                  <p class="text-parchment-dim text-xs">
                    {(appt.client && appt.client.name) || appt.external_client_name} · {Calendar.strftime(
                      appt.scheduled_at,
                      "%b %d, %Y %H:%M"
                    )}
                  </p>
                </div>
                <%= if appt.client_id do %>
                  <a
                    href={"/nutritionist/clients/#{appt.client_id}"}
                    class="text-paprika hover:text-paprika-soft text-xs"
                  >View client</a>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
