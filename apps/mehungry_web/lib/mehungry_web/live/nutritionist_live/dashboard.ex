defmodule MehungryWeb.NutritionistLive.Dashboard do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile

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
      |> assign(:show_profile_form, is_nil(profile))
      |> assign(:profile_changeset, profile_changeset(profile, user.id))

    {:ok, socket}
  end

  @impl true
  def handle_event("save_profile", %{"professional_profile" => params}, socket) do
    user = socket.assigns.current_user
    attrs = Map.put(params, "user_id", user.id)

    result =
      case socket.assigns.profile do
        nil -> Professionals.create_professional_profile(attrs)
        profile -> Professionals.update_professional_profile(profile, attrs)
      end

    case result do
      {:ok, profile} ->
        {:noreply,
         socket
         |> assign(:profile, profile)
         |> assign(:show_profile_form, false)
         |> put_flash(:info, "Profile saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("edit_profile", _params, socket) do
    {:noreply, assign(socket, :show_profile_form, true)}
  end

  defp profile_changeset(nil, user_id) do
    Professionals.change_professional_profile(%ProfessionalProfile{}, %{user_id: user_id})
  end

  defp profile_changeset(profile, _user_id) do
    Professionals.change_professional_profile(profile)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <h1 class="text-2xl font-bold text-white mb-6">Dashboard</h1>

      <%= if @show_profile_form do %>
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-6 mb-6">
          <h2 class="text-lg font-semibold text-white mb-4">Complete your professional profile</h2>
          <.form :let={f} for={@profile_changeset} phx-submit="save_profile" class="space-y-4">
            <div>
              <label class="block text-sm text-slate-300 mb-1">Specialization</label>
              <.input
                field={f[:specialization]}
                type="text"
                placeholder="e.g. Nutritionist, Dietitian, Sports Dietitian…"
                class="w-full"
              />
            </div>
            <div>
              <label class="block text-sm text-slate-300 mb-1">Bio</label>
              <.input field={f[:bio]} type="textarea" rows="3" class="w-full" />
            </div>
            <.button type="submit" class="btn btn-primary">Save Profile</.button>
          </.form>
        </div>
      <% else %>
        <%= if @profile do %>
          <div class="bg-slate-800 border border-slate-700 rounded-xl p-4 mb-6 flex items-center justify-between">
            <div>
              <p class="text-white font-medium capitalize">{@profile.specialization}</p>
              <%= if @profile.bio do %>
                <p class="text-slate-400 text-sm mt-1">{@profile.bio}</p>
              <% end %>
            </div>
            <button phx-click="edit_profile" class="text-sm text-teal-400 hover:text-teal-300">Edit</button>
          </div>
        <% end %>
      <% end %>

      <!-- Stats -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <p class="text-slate-400 text-sm">Active Clients</p>
          <p class="text-3xl font-bold text-white mt-1">{@client_count}</p>
          <a href="/nutritionist/clients" class="text-teal-400 text-xs mt-2 block hover:underline">View all →</a>
        </div>
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <p class="text-slate-400 text-sm">Pending Invitations</p>
          <p class="text-3xl font-bold text-white mt-1">{@pending_invitations_sent}</p>
          <a href="/nutritionist/invitations" class="text-teal-400 text-xs mt-2 block hover:underline">Manage →</a>
        </div>
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <p class="text-slate-400 text-sm">Upcoming Appointments</p>
          <p class="text-3xl font-bold text-white mt-1">{length(@upcoming_appointments)}</p>
          <a
            href="/nutritionist/appointments"
            class="text-teal-400 text-xs mt-2 block hover:underline"
          >Calendar →</a>
        </div>
      </div>

      <!-- Upcoming appointments -->
      <%= if length(@upcoming_appointments) > 0 do %>
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-white font-semibold mb-4">Upcoming Appointments</h2>
          <div class="space-y-3">
            <%= for appt <- @upcoming_appointments do %>
              <div class="flex items-center justify-between py-2 border-b border-slate-700 last:border-0">
                <div>
                  <p class="text-white text-sm font-medium">{appt.title}</p>
                  <p class="text-slate-400 text-xs">
                    {(appt.client && appt.client.name) || appt.external_client_name} · {Calendar.strftime(
                      appt.scheduled_at,
                      "%b %d, %Y %H:%M"
                    )}
                  </p>
                </div>
                <%= if appt.client_id do %>
                  <a
                    href={"/nutritionist/clients/#{appt.client_id}"}
                    class="text-teal-400 text-xs hover:underline"
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
