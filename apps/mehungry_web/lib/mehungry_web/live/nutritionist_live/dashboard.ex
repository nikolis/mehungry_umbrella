defmodule MehungryWeb.NutritionistLive.Dashboard do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.MealBlueprints

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    profile = Professionals.get_professional_profile(user.id)
    client_count = Professionals.count_clients(user.id)
    upcoming = Professionals.list_upcoming_appointments(user.id, 5)
    blueprint_count = length(MealBlueprints.list_blueprints_for_user(user.id))

    pending_sent =
      length(Enum.filter(Professionals.list_sent_invitations(user.id), &(&1.status == "pending")))

    setup_steps = setup_steps(profile, client_count, pending_sent, blueprint_count)

    socket =
      socket
      |> assign(:profile, profile)
      |> assign(:client_count, client_count)
      |> assign(:upcoming_appointments, upcoming)
      |> assign(:pending_invitations_sent, pending_sent)
      |> assign(:blueprint_count, blueprint_count)
      |> assign(:setup_steps, setup_steps)
      |> assign(:setup_complete?, Enum.all?(setup_steps, & &1.done))
      |> assign(:page_title, "Nutritionist Dashboard")

    {:ok, socket}
  end

  # The activation path a nutritionist walks to a fully usable practice. Every
  # signal is already loaded in mount (no extra queries). The checklist replaces
  # the old single "set up profile" banner so scattered manual setup becomes one
  # guided, self-ticking sequence. The client step honors its "or invite" promise
  # by ticking on either an accepted client or a still-pending sent invitation.
  defp setup_steps(profile, client_count, pending_invitations_sent, blueprint_count) do
    [
      %{
        label: "Create your professional profile",
        done: not is_nil(profile),
        href: "/nutritionist/profile",
        cta: "Set up"
      },
      %{
        label: "Publish your profile so clients can find you",
        done: (profile && profile.is_public) || false,
        href: "/nutritionist/profile",
        cta: "Publish"
      },
      %{
        label: "Add or invite your first client",
        done: client_count > 0 or pending_invitations_sent > 0,
        href: "/nutritionist/clients",
        cta: "Add client"
      },
      %{
        label: "Draft your first meal-plan blueprint",
        done: blueprint_count > 0,
        href: "/nutritionist/blueprints",
        cta: "Create"
      }
    ]
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <h1 class="text-2xl font-display font-bold text-parchment mb-1">Dashboard</h1>
      <p class="text-parchment-dim text-sm mb-6">
        AI drafts the plans · you review & approve · your advice stays 100% yours — every recipe built on exact USDA nutrition (168 nutrients per serving).
      </p>

      <%= if @profile do %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-4 mb-6 flex items-center justify-between">
          <div>
            <p class="text-parchment font-medium capitalize">
              {@profile.display_name || @profile.specialization}
            </p>
            <p class="text-parchment-dim text-sm mt-1">
              <%= if @profile.is_public do %>
                Public ·
                <a
                  href={"/nutritionists/#{@profile.slug}"}
                  class="text-paprika hover:text-paprika-soft"
                >view page</a>
              <% else %>
                Not published yet
              <% end %>
            </p>
          </div>
          <a href="/nutritionist/profile" class="text-sm text-paprika hover:text-paprika-soft">Edit profile</a>
        </div>
      <% end %>

      <!-- Activation checklist (until the practice is fully set up) -->
      <%= if not @setup_complete? do %>
        <div class="bg-basil/10 border border-basil/30 rounded-xl p-5 mb-6">
          <p class="text-parchment font-medium mb-1">Set up your practice</p>
          <p class="text-parchment-dim text-sm mb-4">
            A few steps to get discovered and start seeing clients.
          </p>
          <ul class="space-y-2">
            <li :for={step <- @setup_steps} class="flex items-center justify-between gap-3">
              <div class="flex items-center gap-2 min-w-0">
                <%= if step.done do %>
                  <.icon name="hero-check-circle-solid" class="h-5 w-5 text-basil flex-shrink-0" />
                  <span class="text-parchment-dim text-sm line-through truncate">{step.label}</span>
                <% else %>
                  <span class="h-5 w-5 rounded-full border border-parchment-dim/40 flex-shrink-0"></span>
                  <span class="text-parchment text-sm truncate">{step.label}</span>
                <% end %>
              </div>
              <a
                :if={not step.done}
                href={step.href}
                class="text-sm font-medium text-paprika hover:text-paprika-soft whitespace-nowrap"
              >{step.cta} →</a>
            </li>
          </ul>
        </div>
      <% end %>

      <!-- Stats -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Active Clients</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">
            {@client_count}
          </p>
          <a
            href="/nutritionist/clients"
            class="text-paprika hover:text-paprika-soft text-xs mt-2 block"
          >View all →</a>
        </div>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Pending Invitations</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">
            {@pending_invitations_sent}
          </p>
          <a
            href="/nutritionist/invitations"
            class="text-paprika hover:text-paprika-soft text-xs mt-2 block"
          >Manage →</a>
        </div>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Upcoming Appointments</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">
            {length(@upcoming_appointments)}
          </p>
          <a
            href="/nutritionist/appointments"
            class="text-paprika hover:text-paprika-soft text-xs mt-2 block"
          >Calendar →</a>
        </div>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <p class="text-parchment-dim text-sm">Meal Blueprints</p>
          <p class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums] mt-1">
            {@blueprint_count}
          </p>
          <a
            href="/nutritionist/blueprints"
            class="text-paprika hover:text-paprika-soft text-xs mt-2 block"
          >Author & share →</a>
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
