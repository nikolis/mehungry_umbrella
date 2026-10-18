defmodule MehungryWeb.NutritionistLive.ClientCalendar do
  use MehungryWeb, :live_view
  use ViewportHelpers

  alias Mehungry.Professionals
  alias Mehungry.Accounts
  alias Mehungry.History
  alias Mehungry.History.UserMeal
  alias Mehungry.Food

  @impl true
  def mount(%{"id" => client_id_str} = _params, _session, socket) do
    professional_id = socket.assigns.current_user.id
    client_id = String.to_integer(client_id_str)

    case Professionals.get_assignment(professional_id, client_id) do
      nil ->
        {:ok,
         socket |> put_flash(:error, "Client not found.") |> redirect(to: "/nutritionist/clients")}

      _assignment ->
        client = Accounts.get_user!(client_id)
        user_meals = load_and_format_user_meals(client_id, Date.utc_today())
        recipes = Food.list_user_recipes_for_selection(nil)

        socket = assign_device_kind(socket)
        socket = push_event(socket, "create_meals", %{meals: user_meals})

        {:ok,
         socket
         |> assign(:client, client)
         |> assign(:client_id, client_id)
         |> assign(:user_meals, user_meals)
         |> assign(:recipes, recipes)
         |> assign(:particular_date, nil)
         |> assign(:calendar_view, "week_view")
         |> assign(:child_ids, [])
         |> assign(:page_title, "#{client.name || client.email}'s Meal Plan")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: socket

  defp apply_action(socket, :particular, %{"date" => date}) do
    # Week navigation patches here with no reload of its own, so load the
    # newly-viewed week's meals (the calendar only ever shows one week).
    socket = assign(socket, :particular_date, date)

    socket
    |> push_event("go_to_date", %{date: date})
    |> assign(
      :user_meals,
      load_and_format_user_meals(socket.assigns.client_id, current_calendar_date(socket))
    )
  end

  defp apply_action(socket, :new, %{"date" => start_date, "title" => title}) do
    if past_date?(start_date) do
      deny_past_date(socket)
    else
      socket
      |> assign(:page_title, "Create Meal")
      |> assign(:user_meal, struct(UserMeal))
      |> assign(:title, title)
      |> assign(:dates, %{start: start_date})
    end
  end

  defp apply_action(socket, :edit, %{"meal_id" => meal_id}) do
    user_meal = History.get_user_meal!(meal_id)

    cond do
      # Guard: nutritionists may only edit meals belonging to their assigned client.
      user_meal.user_id != socket.assigns.client_id ->
        socket
        |> put_flash(:error, "Not authorized.")
        |> push_patch(to: "/nutritionist/clients/#{socket.assigns.client_id}/calendar")

      past_date?(user_meal.start_dt) ->
        deny_past_date(socket)

      true ->
        socket
        |> assign(:page_title, "Edit Meal")
        |> assign(:user_meal, user_meal)
        |> assign(:title, user_meal.title)
        |> assign(:dates, %{start: user_meal.start_dt, end: user_meal.end_dt})
    end
  end

  # Meals can only be assigned or edited from today forward; past dates are
  # read-only. Both the widget's add/edit affordances route through the `:new`
  # and `:edit` actions, so guarding here covers every entry point (including
  # direct URL navigation).
  defp past_date?(%NaiveDateTime{} = dt),
    do: Date.compare(NaiveDateTime.to_date(dt), Date.utc_today()) == :lt

  defp past_date?(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> Date.compare(d, Date.utc_today()) == :lt
      _ -> false
    end
  end

  defp deny_past_date(socket) do
    socket
    |> put_flash(:error, "You can't assign meals on a past date — pick today or a future day.")
    |> push_patch(to: "/nutritionist/clients/#{socket.assigns.client_id}/calendar")
  end

  @impl true
  def handle_info({:initial_modal, %{"date" => start_date, "title" => title}}, socket) do
    client_id = socket.assigns.client_id

    {:noreply,
     push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/#{start_date}/#{title}")}
  end

  @impl true
  def handle_info({:particular_date, %{"date" => date}}, socket) do
    client_id = socket.assigns.client_id
    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/#{date}")}
  end

  @impl true
  def handle_event("delete_user_meal", %{"id" => id}, socket) do
    client_id = socket.assigns.client_id

    try do
      meal = History.get_user_meal!(String.to_integer(id))

      if meal.user_id == client_id do
        History.delete_user_meal(meal)
        user_meals = load_and_format_user_meals(client_id, current_calendar_date(socket))

        {:noreply,
         socket
         |> assign(:user_meals, user_meals)
         |> push_event("create_meals", %{meals: user_meals})}
      else
        {:noreply, put_flash(socket, :error, "Not authorized.")}
      end
    rescue
      Ecto.NoResultsError -> {:noreply, put_flash(socket, :error, "Meal not found.")}
    end
  end

  @impl true
  def handle_event("go_to_date", %{"date" => date}, socket) do
    client_id = socket.assigns.client_id
    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/#{date}")}
  end

  @impl true
  def handle_event("edit_modal", %{"id" => id}, socket) do
    client_id = socket.assigns.client_id

    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar/edit/#{id}")}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    client_id = socket.assigns.client_id
    {:noreply, push_patch(socket, to: "/nutritionist/clients/#{client_id}/calendar")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-ink min-h-screen">
      <.modal
        :if={@live_action in [:new, :edit]}
        on_cancel={JS.patch("/nutritionist/clients/#{@client_id}/calendar")}
        id="client_calendar_modal"
        show
      >
        <div class="w-full h-full">
          <.live_component
            module={MehungryWeb.CalendarLive.MealFormComponent}
            id={@user_meal.id || :new}
            title={@user_meal.title || @title}
            live_action={@live_action}
            recipes={@recipes}
            dates={@dates}
            current_user={@client}
            return_to={"/nutritionist/clients/#{@client_id}/calendar"}
          />
        </div>
      </.modal>
      <!-- Banner -->
      <div class="bg-basil/10 border-b border-basil/30 px-4 py-2 flex items-center gap-3">
        <a href={"/nutritionist/clients/#{@client_id}"} class="text-basil hover:text-basil-soft">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
        </a>
        <%= if @client.profile_pic do %>
          <img src={@client.profile_pic} class="w-6 h-6 rounded-full object-cover" />
        <% else %>
          <div class="w-6 h-6 rounded-full bg-basil flex items-center justify-center text-ink text-xs font-bold">
            {String.first(@client.name || "?")}
          </div>
        <% end %>
        <p class="text-parchment-dim text-sm">
          Editing <span class="font-medium text-parchment">{@client.name || @client.email}</span>'s meal plan
        </p>
      </div>

      <!-- Calendar widget (reuses same JS hooks) -->
      <div style="height: calc(100vh - 48px); overflow-y: auto;" class="bg-ink">
        <.live_component
          module={MehungryWeb.CalendarLive.Calendar.Widget}
          id={:new}
          user_meals={@user_meals}
          particular_date={@particular_date}
          title="Meal Plan"
          calendar_view={@calendar_view}
          action={@live_action}
          user={@client}
          device_width={@device_width}
          current_language={@current_language}
        />
      </div>
    </div>
    """
  end

  # Loads only the meals for the week the given date falls in, rather than the
  # client's entire history (the calendar only ever shows one week).
  defp load_and_format_user_meals(user_id, %Date{} = date) do
    first = Date.beginning_of_week(date)
    last = Date.add(first, 6)

    History.list_calendar_user_meals(user_id, first, last)
    |> History.format_user_meals()
  end

  defp current_calendar_date(socket) do
    case socket.assigns[:particular_date] do
      date when is_binary(date) ->
        case Date.from_iso8601(date) do
          {:ok, d} -> d
          _ -> Date.utc_today()
        end

      %Date{} = d ->
        d

      _ ->
        Date.utc_today()
    end
  end
end
