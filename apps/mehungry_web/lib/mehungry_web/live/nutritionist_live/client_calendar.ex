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
        user_meals = load_and_format_user_meals(client_id)
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
    socket
    |> push_event("go_to_date", %{date: date})
    |> assign(:particular_date, date)
  end

  defp apply_action(socket, :new, %{"date" => start_date, "title" => title}) do
    socket
    |> assign(:page_title, "Create Meal")
    |> assign(:user_meal, struct(UserMeal))
    |> assign(:title, title)
    |> assign(:dates, %{start: start_date})
  end

  defp apply_action(socket, :edit, %{"meal_id" => meal_id}) do
    user_meal = History.get_user_meal!(meal_id)

    # Guard: nutritionists may only edit meals belonging to their assigned client.
    if user_meal.user_id == socket.assigns.client_id do
      socket
      |> assign(:page_title, "Edit Meal")
      |> assign(:user_meal, user_meal)
      |> assign(:title, user_meal.title)
      |> assign(:dates, %{start: user_meal.start_dt, end: user_meal.end_dt})
    else
      socket
      |> put_flash(:error, "Not authorized.")
      |> push_patch(to: "/nutritionist/clients/#{socket.assigns.client_id}/calendar")
    end
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
        user_meals = load_and_format_user_meals(client_id)

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
    <div class="bg-slate-900 min-h-screen">
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
      <div class="bg-teal-900/40 border-b border-teal-700/40 px-4 py-2 flex items-center gap-3">
        <a href={"/nutritionist/clients/#{@client_id}"} class="text-teal-400 hover:text-teal-300">
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
          <div class="w-6 h-6 rounded-full bg-teal-600 flex items-center justify-center text-white text-xs font-bold">
            {String.first(@client.name || "?")}
          </div>
        <% end %>
        <p class="text-teal-300 text-sm">
          Editing <span class="font-medium text-white">{@client.name || @client.email}</span>'s meal plan
        </p>
      </div>

      <!-- Calendar widget (reuses same JS hooks) -->
      <div id="page-timer" phx-hook="PageTimer" class="hidden"></div>
      <div style="height: calc(100vh - 48px); overflow-y: auto;" class="bg-slate-900">
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

  defp load_and_format_user_meals(user_id) do
    History.list_history_user_meals_for_user(user_id)
    |> Enum.map(fn x ->
      %{
        id: x.id,
        start_dt: x.start_dt,
        end: x.end_dt,
        title: x.title,
        ingredient_user_meals:
          Enum.map(x.ingredient_user_meals, fn y ->
            %{
              title: y.ingredient.name,
              portions: y.quantity,
              measurement_unit: y.measurement_unit.name,
              primary_size: 6,
              img_url: nil,
              recipe: %{
                id: y.ingredient.id,
                nutrients:
                  Enum.map(y.ingredient.ingredient_nutrients, fn n ->
                    %{
                      amount: n.amount,
                      name: n.nutrient.name,
                      measurement_unit: %{name: n.nutrient.measurement_unit.name}
                    }
                  end),
                primary_size: 5
              }
            }
          end),
        recipe_user_meals:
          Enum.map(x.recipe_user_meals, fn y ->
            %{
              title: y.recipe.title,
              consume_portions: y.consume_portions,
              cooking_portions: y.cooking_portions,
              servings: y.recipe.servings,
              recipe_nutrients: y.recipe.nutrients,
              img_url: y.recipe.image_url,
              primary_size: y.recipe.primary_nutrients_size,
              recipe_id: y.recipe.id
            }
          end)
      }
    end)
  end
end
