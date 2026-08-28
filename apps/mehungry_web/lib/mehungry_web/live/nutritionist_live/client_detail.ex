defmodule MehungryWeb.NutritionistLive.ClientDetail do
  use MehungryWeb, :live_view

  alias Mehungry.Professionals
  alias Mehungry.Accounts
  alias Mehungry.Plans, as: PlansCtx
  alias Mehungry.ObanWorkers.NutritionistAgentWorker

  @impl true
  def mount(%{"id" => client_id}, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id_int = String.to_integer(client_id)

    case Professionals.get_assignment(professional_id, client_id_int) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Client not found.") |> redirect(to: "/nutritionist/clients")}

      _assignment ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(
            Mehungry.PubSub,
            NutritionistAgentWorker.topic(professional_id)
          )
        end

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
         |> assign(:page_title, "Client: #{client.name || client.email}")
         |> assign(:ai_running, false)
         |> assign(:ai_steps, [])
         |> assign(:ai_result, nil)
         |> assign(:ai_error, nil)
         |> assign(:ai_preferences, "")}
    end
  end

  # ── AI Assist events ──────────────────────────────────────────────────────────

  @impl true
  def handle_event("ai_assist", %{"preferences" => prefs}, socket) do
    professional_id = socket.assigns.current_user.id
    client = socket.assigns.client

    case NutritionistAgentWorker.enqueue(
           professional_id,
           socket.assigns.client_id,
           client.name || client.email,
           prefs
         ) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:ai_running, true)
         |> assign(:ai_steps, [])
         |> assign(:ai_result, nil)
         |> assign(:ai_error, nil)
         |> assign(:ai_preferences, prefs)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start AI assistant: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("ai_dismiss", _params, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, false)
     |> assign(:ai_steps, [])
     |> assign(:ai_result, nil)
     |> assign(:ai_error, nil)}
  end

  # ── PubSub messages ───────────────────────────────────────────────────────────

  @impl true
  def handle_info({:nutritionist_agent, {:started, client_name}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, true)
     |> assign(:ai_steps, ["Starting analysis for #{client_name}…"])
     |> assign(:ai_result, nil)
     |> assign(:ai_error, nil)}
  end

  def handle_info({:nutritionist_agent, {:step, label}}, socket) do
    steps = socket.assigns.ai_steps ++ [label]
    {:noreply, assign(socket, :ai_steps, steps)}
  end

  def handle_info({:nutritionist_agent, {:done, summary}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, false)
     |> assign(:ai_result, summary)}
  end

  def handle_info({:nutritionist_agent, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_running, false)
     |> assign(:ai_error, reason)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── render ────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <!-- Header -->
      <div class="flex items-center gap-4 mb-6">
        <a href="/nutritionist/clients" class="text-parchment-dim hover:text-parchment">
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
        </a>
        <%= if @client.profile_pic do %>
          <img src={@client.profile_pic} class="w-12 h-12 rounded-full object-cover" />
        <% else %>
          <div class="w-12 h-12 rounded-full bg-basil flex items-center justify-center text-ink font-bold">
            {String.first(@client.name || "?")}
          </div>
        <% end %>
        <div>
          <h1 class="text-xl font-display font-bold text-parchment">{@client.name || @client.email}</h1>
          <p class="text-parchment-dim text-sm">{@client.email}</p>
        </div>
        <div class="ml-auto flex gap-2">
          <a
            href={"/nutritionist/clients/#{@client_id}/calendar"}
            class="btn btn-sm bg-paprika hover:bg-paprika-soft text-ink border-0"
          >
            Edit Meal Plan
          </a>
          <a
            href={"/nutritionist/appointments?client_id=#{@client_id}"}
            class="btn btn-sm bg-ink-panel2 hover:bg-ink text-parchment border border-ink-panel2"
          >
            Schedule Appointment
          </a>
        </div>
      </div>

      <!-- AI Assist panel -->
      <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mb-6">
        <div class="flex items-center justify-between mb-3">
          <div class="flex items-center gap-2">
            <svg class="w-4 h-4 text-basil" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z"
              />
            </svg>
            <h2 class="text-parchment font-semibold text-sm">AI Meal Plan Assistant</h2>
          </div>
          <%= if @ai_result || @ai_error do %>
            <button phx-click="ai_dismiss" class="text-parchment-dim hover:text-parchment text-xs">
              Dismiss
            </button>
          <% end %>
        </div>

        <%= if not @ai_running and is_nil(@ai_result) and is_nil(@ai_error) do %>
          <!-- Idle state: show form -->
          <.form for={%{}} phx-submit="ai_assist" class="flex gap-2">
            <input
              type="text"
              name="preferences"
              value={@ai_preferences}
              placeholder="Dietary notes for this client, e.g. 'low-carb, avoid shellfish'"
              class="flex-1 bg-ink-panel2 border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-sm placeholder-parchment-dim focus:outline-none focus:border-paprika"
            />
            <button
              type="submit"
              class="bg-paprika hover:bg-paprika-soft text-ink text-sm font-medium px-4 py-2 rounded-lg transition whitespace-nowrap"
            >
              Draft 7-day Plan
            </button>
          </.form>
        <% end %>

        <!-- Running: streaming steps -->
        <%= if @ai_running or @ai_steps != [] do %>
          <div class="space-y-1.5 mt-2">
            <%= for {step, idx} <- Enum.with_index(@ai_steps) do %>
              <div class="flex items-center gap-2">
                <%= if idx == length(@ai_steps) - 1 and @ai_running do %>
                  <!-- Latest step: animated dot -->
                  <span class="w-2 h-2 rounded-full bg-basil animate-pulse shrink-0"></span>
                <% else %>
                  <svg
                    class="w-3.5 h-3.5 text-basil shrink-0"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2.5"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                <% end %>
                <span class={[
                  "text-sm",
                  if(idx == length(@ai_steps) - 1 and @ai_running,
                    do: "text-parchment",
                    else: "text-parchment-dim"
                  )
                ]}>
                  {step}
                </span>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- Done: show result -->
        <%= if @ai_result do %>
          <div class="mt-3 p-3 bg-basil/10 border border-basil/30 rounded-lg">
            <p class="text-basil text-sm whitespace-pre-wrap">{@ai_result}</p>
          </div>
          <div class="mt-3 flex gap-2">
            <a
              href={"/nutritionist/clients/#{@client_id}/calendar"}
              class="text-sm bg-paprika hover:bg-paprika-soft text-ink px-3 py-1.5 rounded-lg transition"
            >
              View Plan →
            </a>
            <button
              phx-click="ai_dismiss"
              class="text-sm bg-ink-panel2 hover:bg-ink text-parchment-dim px-3 py-1.5 rounded-lg transition"
            >
              Draft Another
            </button>
          </div>
        <% end %>

        <!-- Error state -->
        <%= if @ai_error do %>
          <div class="mt-3 p-3 bg-red-900/30 border border-red-700/40 rounded-lg">
            <p class="text-red-300 text-sm">{@ai_error}</p>
          </div>
          <button
            phx-click="ai_dismiss"
            class="mt-2 text-sm text-parchment-dim hover:text-parchment"
          >
            Try again
          </button>
        <% end %>
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <!-- Appointment history -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">Appointment History</h2>
          <%= if Enum.empty?(@appointments) do %>
            <p class="text-parchment-dim text-sm">No appointments yet.</p>
          <% else %>
            <div class="space-y-3 max-h-64 overflow-y-auto">
              <%= for appt <- @appointments do %>
                <div class="border-b border-ink-panel2 pb-3 last:border-0">
                  <div class="flex items-start justify-between">
                    <p class="text-parchment text-sm font-medium">{appt.title}</p>
                    <span class="text-parchment-dim text-xs shrink-0 ml-2">
                      {Calendar.strftime(appt.scheduled_at, "%b %d, %Y")}
                    </span>
                  </div>
                  <%= if appt.notes do %>
                    <p class="text-parchment-dim text-xs mt-1">{appt.notes}</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Meal plan ratings -->
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5">
          <h2 class="text-parchment font-display font-semibold mb-4">Meal Plan Ratings</h2>
          <%= if Enum.empty?(@ratings) do %>
            <p class="text-parchment-dim text-sm">No ratings submitted yet.</p>
          <% else %>
            <div class="space-y-3 max-h-64 overflow-y-auto">
              <%= for rating <- @ratings do %>
                <div class="border-b border-ink-panel2 pb-3 last:border-0">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-1">
                      <%= for i <- 1..5 do %>
                        <svg
                          class={[
                            "w-4 h-4",
                            if(i <= rating.score, do: "text-yellow-400", else: "text-ink-panel2")
                          ]}
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
                    <span class="text-parchment-dim text-xs">
                      {Calendar.strftime(rating.inserted_at, "%b %d")}
                    </span>
                  </div>
                  <%= if rating.comment do %>
                    <p class="text-parchment-dim text-xs mt-1 italic">"{rating.comment}"</p>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Meal plans history -->
      <%= if not Enum.empty?(@meal_plans) do %>
        <div class="bg-ink-panel border border-ink-panel2 rounded-xl p-5 mt-6">
          <h2 class="text-parchment font-display font-semibold mb-4">Meal Plan History</h2>
          <div class="space-y-2">
            <%= for plan <- @meal_plans do %>
              <div class="flex items-center justify-between py-2 border-b border-ink-panel2 last:border-0">
                <div>
                  <p class="text-parchment text-sm">{plan.title}</p>
                  <p class="text-parchment-dim text-xs">{plan.description}</p>
                </div>
                <span class="text-parchment-dim text-xs">
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
