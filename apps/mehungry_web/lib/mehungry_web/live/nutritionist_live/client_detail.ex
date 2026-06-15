defmodule MehungryWeb.NutritionistLive.ClientDetail do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Accounts
  alias Mehungry.Plans, as: PlansCtx

  @impl true
  def mount(%{"id" => client_id}, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id_int = String.to_integer(client_id)

    # Verify this is actually one of our clients
    case Professionals.get_assignment(professional_id, client_id_int) do
      nil ->
        {:ok, socket |> put_flash(:error, "Client not found.") |> redirect(to: "/nutritionist/clients")}

      _assignment ->
        client = Accounts.get_user!(client_id_int)
        appointments = Professionals.list_appointments_for_client(client_id_int)
        ratings = Professionals.list_ratings_for_client(client_id_int)
        meal_plans = PlansCtx.list_meal_plans_for_user(client_id_int)

        {:ok,
         socket
         |> assign(:client, client)
         |> assign(:client_id, client_id_int)
         |> assign(:appointments, appointments)
         |> assign(:ratings, ratings)
         |> assign(:meal_plans, meal_plans)
         |> assign(:page_title, "Client: #{client.name || client.email}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <!-- Header -->
      <div class="flex items-center gap-4 mb-6">
        <a href="/nutritionist/clients" class="text-slate-400 hover:text-white">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 19l-7-7m0 0l7-7m-7 7h18" />
          </svg>
        </a>
        <%= if @client.profile_pic do %>
          <img src={@client.profile_pic} class="w-12 h-12 rounded-full object-cover" />
        <% else %>
          <div class="w-12 h-12 rounded-full bg-teal-600 flex items-center justify-center text-white font-bold">
            {String.first(@client.name || "?")}
          </div>
        <% end %>
        <div>
          <h1 class="text-xl font-bold text-white">{@client.name || @client.email}</h1>
          <p class="text-slate-400 text-sm">{@client.email}</p>
        </div>
        <div class="ml-auto flex gap-2">
          <a
            href={"/nutritionist/clients/#{@client_id}/calendar"}
            class="btn btn-sm bg-teal-600 hover:bg-teal-500 text-white border-0"
          >
            Edit Meal Plan
          </a>
          <a
            href={"/nutritionist/appointments?client_id=#{@client_id}"}
            class="btn btn-sm bg-slate-700 hover:bg-slate-600 text-white border-0"
          >
            Schedule Appointment
          </a>
        </div>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Appointment history -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-white font-semibold mb-4">Appointment History</h2>
          <%= if Enum.empty?(@appointments) do %>
            <p class="text-slate-500 text-sm">No appointments yet.</p>
          <% else %>
            <div class="space-y-3 max-h-64 overflow-y-auto">
              <%= for appt <- @appointments do %>
                <div class="border-b border-slate-700 pb-3 last:border-0">
                  <div class="flex items-start justify-between">
                    <p class="text-white text-sm font-medium">{appt.title}</p>
                    <span class="text-slate-500 text-xs shrink-0 ml-2">
                      {Calendar.strftime(appt.scheduled_at, "%b %d, %Y")}
                    </span>
                  </div>
                  <%= if appt.notes do %>
                    <p class="text-slate-400 text-xs mt-1">{appt.notes}</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Meal plan ratings -->
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5">
          <h2 class="text-white font-semibold mb-4">Meal Plan Ratings</h2>
          <%= if Enum.empty?(@ratings) do %>
            <p class="text-slate-500 text-sm">No ratings submitted yet.</p>
          <% else %>
            <div class="space-y-3 max-h-64 overflow-y-auto">
              <%= for rating <- @ratings do %>
                <div class="border-b border-slate-700 pb-3 last:border-0">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-1">
                      <%= for i <- 1..5 do %>
                        <svg
                          class={["w-4 h-4", if(i <= rating.score, do: "text-yellow-400", else: "text-slate-600")]}
                          fill="currentColor"
                          viewBox="0 0 20 20"
                        >
                          <path d="M9.049 2.927c.3-.921 1.603-.921 1.902 0l1.07 3.292a1 1 0 00.95.69h3.462c.969 0 1.371 1.24.588 1.81l-2.8 2.034a1 1 0 00-.364 1.118l1.07 3.292c.3.921-.755 1.688-1.54 1.118l-2.8-2.034a1 1 0 00-1.175 0l-2.8 2.034c-.784.57-1.838-.197-1.539-1.118l1.07-3.292a1 1 0 00-.364-1.118L2.98 8.72c-.783-.57-.38-1.81.588-1.81h3.461a1 1 0 00.951-.69l1.07-3.292z" />
                        </svg>
                      <% end %>
                      <span class={[
                        "text-xs px-2 py-0.5 rounded-full ml-1",
                        rating.rating_type == "daily" && "bg-blue-500/20 text-blue-400",
                        rating.rating_type == "weekly" && "bg-purple-500/20 text-purple-400"
                      ]}>
                        {String.capitalize(rating.rating_type)}
                      </span>
                    </div>
                    <span class="text-slate-500 text-xs">
                      {Calendar.strftime(rating.inserted_at, "%b %d")}
                    </span>
                  </div>
                  <%= if rating.comment do %>
                    <p class="text-slate-400 text-xs mt-1 italic">"{rating.comment}"</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Meal plans history -->
      <%= if not Enum.empty?(@meal_plans) do %>
        <div class="bg-slate-800 border border-slate-700 rounded-xl p-5 mt-6">
          <h2 class="text-white font-semibold mb-4">Meal Plan History</h2>
          <div class="space-y-2">
            <%= for plan <- @meal_plans do %>
              <div class="flex items-center justify-between py-2 border-b border-slate-700 last:border-0">
                <div>
                  <p class="text-white text-sm">{plan.title}</p>
                  <p class="text-slate-500 text-xs">{plan.description}</p>
                </div>
                <span class="text-slate-500 text-xs">
                  {Calendar.strftime(plan.inserted_at, "%b %d, %Y")}
                </span>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
