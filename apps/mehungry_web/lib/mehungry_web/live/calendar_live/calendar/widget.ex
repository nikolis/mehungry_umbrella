defmodule MehungryWeb.CalendarLive.Calendar.Widget do
  use MehungryWeb, :live_component

  alias MehungryWeb.CalendarLive.Calendar.Utils
  alias MehungryWeb.SvgComponents

  alias Mehungry.NutrientUtils, as: Nu

  def get_chart(user_meals, day, _text) do
    meals = Enum.filter(user_meals, fn x -> NaiveDateTime.to_date(x.start_dt) == day end)

    if meals == [] do
      nil
    else
      total_nutrients = Nu.summarize_meals_nutrients(meals)
      nutrients_sorted = Mehungry.Food.RecipeUtils.sort_nutrients_from_db(total_nutrients)

      meal_count = length(meals)

      total_items =
        Enum.sum(
          Enum.map(meals, fn m ->
            length(m.recipe_user_meals) + length(m.ingredient_user_meals)
          end)
        )

      extract = fn key ->
        case Enum.find(nutrients_sorted, fn {{label, _}, _} -> String.contains?(label, key) end) do
          {{_, %{"amount" => a}}, _} -> a * 1.0
          _ -> 0.0
        end
      end

      energy_kcal = extract.("Energy") |> round()
      protein_g = extract.("Protein") |> Float.round(1)
      carbs_g = extract.("Carbohydrates") |> Float.round(1)
      fat_g = extract.("Total Fat") |> Float.round(1)

      data =
        nutrients_sorted
        |> Enum.reject(fn {{label, _}, _} -> String.contains?(label, "Energy") end)
        |> Enum.take(5)
        |> Enum.map(fn {{label, %{"amount" => amount}}, _} ->
          cleaned =
            label
            |> String.replace("\n", " ")
            |> String.replace(~r/\s+/, " ")
            |> String.trim()

          %{category: cleaned, value: amount}
        end)

      recipe = %{
        nutrients: total_nutrients,
        id: "overview_#{Date.to_string(day)}",
        primary_size: 5
      }

      assigns = %{
        recipe: recipe,
        data: data,
        day: day,
        meal_count: meal_count,
        total_items: total_items,
        energy_kcal: energy_kcal,
        protein_g: protein_g,
        carbs_g: carbs_g,
        fat_g: fat_g
      }

      ~H"""
      <div class="mt-2 rounded-xl border border-slate-600 overflow-hidden bg-slate-800">
        <div class="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3 bg-slate-700/50 border-b border-slate-700">
          <span class="text-slate-200 font-semibold text-sm">Daily Summary</span>
          <div class="flex flex-wrap gap-2 ml-auto">
            <span class="px-2.5 py-0.5 rounded-full bg-slate-700 text-slate-300 text-xs">
              {@meal_count} meal{if @meal_count != 1, do: "s"} · {@total_items} item{if @total_items !=
                                                                                          1,
                                                                                        do: "s"}
            </span>
            <span class="px-2.5 py-0.5 rounded-full bg-primary-500/20 text-primary-300 text-xs font-semibold">
              {@energy_kcal} kcal
            </span>
            <span class="px-2.5 py-0.5 rounded-full bg-slate-700 text-slate-300 text-xs">
              {@protein_g}g protein
            </span>
            <span class="px-2.5 py-0.5 rounded-full bg-slate-700 text-slate-300 text-xs">
              {@carbs_g}g carbs
            </span>
            <span class="px-2.5 py-0.5 rounded-full bg-slate-700 text-slate-300 text-xs">
              {@fat_g}g fat
            </span>
          </div>
        </div>
        <div class="flex flex-col sm:flex-row min-h-0">
          <div
            class="flex-1 sm:border-r border-b sm:border-b-0 border-slate-700 overflow-y-auto"
            style="max-height: 400px;"
          >
            {MehungryWeb.RecipeComponents.recipe_nutrients(@recipe)}
          </div>
          <div class="flex-1 flex items-center justify-center p-4 sm:p-6">
            <.live_component
              module={MehungryWeb.CalendarLive.Calendar.PieChart}
              id={"nutrition-chart23" <> Date.to_string(@day)}
              data={@data}
              origin_id={"nutrition-chart23" <> Date.to_string(@day)}
              size="20rem"
            />
          </div>
        </div>
      </div>
      """
    end
  end

  @day_meals ["breakfast", "elevenses", "lunch", "after lunch", "dinner"]
  @impl true
  def render(assigns) do
    case is_nil(assigns.device_width) do
      true ->
        SvgComponents.get_loading(assigns)

      false ->
        ~H"""
        <div class="bg-slate-900 pb-20" id="calendar_widget">
          <div class="relative flex items-center px-3 py-3 sm:px-4">
            <.button_add_meal current_date={@current_date} myself={@myself} />

            <div class="flex px-3 py-2 gap-3 bg-slate-800 justify-center border border-slate-700 rounded-full mx-auto w-fit shadow-lg">
              <button
                type="button"
                class="w-fit text-slate-400 hover:text-white transition-colors"
                phx-target={@myself}
                phx-click="prev-month"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="2.5"
                  stroke="currentColor"
                  class="size-5"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
                </svg>
              </button>

              <h3 class="text-center text-lg font-semibold text-white">
                <span>{day_name(@current_date, (assigns[:current_language] || "en"))},</span>
                <span>{String.slice(Calendar.strftime(@current_date, "%d"), 0..2)}</span>
                <span>{month_short(@current_date, (assigns[:current_language] || "en"))}</span>
              </h3>

              <button
                type="button"
                class="w-fit text-end text-primary-500 hover:text-primary-400 transition-colors font-medium"
                phx-target={@myself}
                phx-click="next-month"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="2.5"
                  stroke="currentColor"
                  class="size-5"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
                </svg>
              </button>
            </div>
          </div>
          <.table_week_calendar
            week_rows={@week_rows}
            first={@first}
            last={@last}
            user_meals={@user_meals}
            day_meals={@day_meals}
            current_date={@current_date}
            selected_date={@selected_date}
            myself={@myself}
            current_language={@current_language}
          />
        </div>
        """
    end
  end

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :current_language, "en")}
  end

  @impl true
  def update(assigns, socket) do
    current_date =
      case assigns.particular_date do
        nil ->
          Utils.calculate_initial_date(Date.utc_today(), assigns.device_width)

        date ->
          {:ok, date} = Date.from_iso8601(date)
          date
      end

    {first, last, rows} = get_full_week(current_date, assigns.user_meals, 1500)
    language = Map.get(assigns, :current_language, "en")

    assigns = [
      current_date: current_date,
      selected_date: nil,
      user_meals: assigns.user_meals,
      selected_meal: nil,
      week_rows: rows,
      last: last,
      first: first,
      calendar_view: assigns.calendar_view,
      day_meals: @day_meals,
      device_width: assigns.device_width,
      current_language: language
    ]

    {:ok,
     socket
     |> assign(assigns)}
  end

  ## ------------------------------------ Utility Functions  ---------------------------------------------------------------

  defp get_full_week(current_date, _user_meals, _device_width) do
    days = 6
    first = Date.beginning_of_week(current_date)

    last = Date.add(first, days)

    week_rows =
      Date.range(first, last)
      |> Enum.map(& &1)
      |> Enum.chunk_every(7)

    {first, last, week_rows}
  end

  defp get_week_rows(current_date, _user_meals, _device_width) do
    week_rows =
      Date.range(current_date, current_date)
      |> Enum.map(& &1)
      |> Enum.chunk_every(7)

    {current_date, current_date, week_rows}
  end

  ## ------------------------------------ Event Handlers  ---------------------------------------------------------------

  @impl true
  def handle_event("prev-month", _, socket) do
    days = 0
    new_date = socket.assigns.current_date |> Date.add(days) |> Date.add(-1)

    {first, last, rows} =
      get_full_week(new_date, socket.assigns.user_meals, 100)

    assigns = [
      current_date: new_date,
      week_rows: rows,
      last: last,
      first: first
    ]

    send(self(), {:particular_date, %{"date" => new_date}})
    {:noreply, assign(socket, assigns)}
  end

  def handle_event("next-month", _, socket) do
    new_date = socket.assigns.current_date |> Date.add(1)

    {first, last, rows} =
      get_week_rows(new_date, socket.assigns.user_meals, 300)

    assigns = [
      current_date: new_date,
      week_rows: rows,
      last: last,
      first: first
    ]

    send(self(), {:particular_date, %{"date" => first}})
    {:noreply, assign(socket, assigns)}
  end

  def handle_event("pick-date", %{"date" => date}, socket) do
    current_date = date
    send(self(), {:initial_modal, %{"date" => current_date, "title" => "r"}})

    {:noreply, assign(socket, :selected_date, current_date)}
  end

  def handle_event("pick-date", %{"meal" => meal}, socket) do
    current_date = socket.assigns.current_date
    send(self(), {:initial_modal, %{"date" => current_date, "title" => meal}})

    {:noreply,
     assign(socket, :selected_date, current_date)
     |> assign(:selected_meal, meal)}
  end

  def handle_event("date-details", %{"date" => date}, socket) do
    send(self(), {:date_details, %{"date" => date}})

    {:noreply, socket}
  end

  ## ------------------------------------ UI Elements ---------------------------------------------------------------
  def table_week_calendar(assigns) do
    ~H"""
    <div
      :for={week <- @week_rows}
      class="px-3 sm:px-4 pt-2"
    >
      <div :for={day <- week} class="mb-2">
        <div
          class="bg-slate-800 border border-slate-700 rounded-xl overflow-hidden day_of_week"
          id={"dat_" <> Date.to_string(day)}
        >
          <div class="flex items-center gap-2 px-3 py-3 sm:px-4 bg-slate-700/50 border-b border-slate-700/50">
            <span
              class="flex items-center gap-2 text-white font-semibold text-sm sm:text-base cursor-pointer hover:text-primary-400 transition-colors"
              phx-target={@myself}
              phx-click="pick-date"
              phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="size-4 text-primary-500 flex-shrink-0"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v6m3-3H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                />
              </svg>
              {day_name(day, (assigns[:current_language] || "en"))}
            </span>
            <span class="text-slate-500 text-xs sm:text-sm">
              {Calendar.strftime(day, "%d")} {month_short(day, (assigns[:current_language] || "en"))}
            </span>
            <span
              class="ml-auto text-slate-400 hover:text-white transition-colors cursor-pointer p-1"
              phx-click={
                Phoenix.LiveView.JS.toggle_class("copen", to: "#dat_" <> Date.to_string(day))
                |> Phoenix.LiveView.JS.toggle_class("copen", to: "#widget" <> Date.to_string(day))
              }
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="size-5 widget_day"
                id={"widget" <> Date.to_string(day)}
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
              </svg>
            </span>
          </div>

          <div>
            <% day_meals =
              Enum.filter(@user_meals, fn x -> NaiveDateTime.to_date(x.start_dt) == day end) %>
            <%= if day_meals == [] do %>
              <div class="flex flex-col items-center gap-3 py-8 px-4">
                <div class="w-14 h-14 rounded-full bg-slate-700/60 border border-slate-600/50 flex items-center justify-center">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.2"
                    stroke="currentColor"
                    class="size-7 text-slate-500"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M12 8.25v-1.5m0 1.5c-1.355 0-2.697.056-4.024.166C6.845 8.51 6 9.473 6 10.608v2.513m6-4.871c1.355 0 2.697.056 4.024.166C17.155 8.51 18 9.473 18 10.608v2.513M15 8.25v-1.5m-6 1.5v-1.5m12 9.75-1.5.75a3.354 3.354 0 0 1-3 0 3.354 3.354 0 0 0-3 0 3.354 3.354 0 0 1-3 0 3.354 3.354 0 0 0-3 0 3.354 3.354 0 0 1-1.5-.75M3 13.5l1.5.75a3.354 3.354 0 0 0 3 0 3.354 3.354 0 0 1 3 0 3.354 3.354 0 0 0 3 0 3.354 3.354 0 0 1 3 0 3.354 3.354 0 0 0 1.5-.75M3 13.5v6.75a.75.75 0 0 0 .75.75h16.5a.75.75 0 0 0 .75-.75V13.5"
                    />
                  </svg>
                </div>
                <div class="text-center">
                  <p class="text-slate-400 text-sm font-medium">No meals planned</p>
                  <p class="text-slate-600 text-xs mt-0.5">
                    Tap <span class="text-primary-500 font-semibold">+</span> to add one
                  </p>
                </div>
              </div>
            <% else %>
              <div class="p-2 sm:p-3 space-y-2">
                <%= for meal <- day_meals do %>
                  <%= for re_u_m <- meal.recipe_user_meals do %>
                    <%= if NaiveDateTime.to_date(meal.start_dt) == day do %>
                      <.card_meal
                        card_meal_text="text-white"
                        actual_meal={meal}
                        img_url={re_u_m.img_url}
                        title={re_u_m.title}
                        nutrients={re_u_m.recipe_nutrients}
                        cooking_portions={re_u_m.cooking_portions}
                        consume_portions={re_u_m.consume_portions}
                        myself={@myself}
                        recipe={
                          %{
                            nutrients: re_u_m.recipe_nutrients,
                            primary_size: re_u_m.primary_size,
                            servings: re_u_m.servings,
                            id: Integer.to_string(re_u_m.recipe_id) <> Integer.to_string(meal.id)
                          }
                        }
                      />
                    <% end %>
                  <% end %>
                  <%= for re_u_m <- meal.ingredient_user_meals do %>
                    <%= if NaiveDateTime.to_date(meal.start_dt) == day do %>
                      <.card_meal
                        card_meal_text="text-white"
                        myself={@myself}
                        actual_meal={meal}
                        img_url={re_u_m.img_url}
                        title={re_u_m.title}
                        cooking_portions={re_u_m.portions}
                        consume_portions={nil}
                        recipe={
                          %{
                            nutrients:
                              Mehungry.Food.RecipeUtils.reform_nutrients(re_u_m.recipe.nutrients),
                            primary_size: re_u_m.primary_size,
                            servings: re_u_m.portions,
                            id: Integer.to_string(re_u_m.recipe.id) <> Integer.to_string(meal.id)
                          }
                        }
                      />
                    <% end %>
                  <% end %>
                <% end %>
                {get_chart(@user_meals, day, "text-white")}
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def table_day_calendar(assigns) do
    user_meals =
      Enum.filter(assigns.user_meals, fn x ->
        NaiveDateTime.to_date(x.start_dt) == assigns.current_date
      end)

    assigns = Map.put(assigns, :user_meals, user_meals)

    ~H"""
    <div
      :for={week <- @week_rows}
      class="h-full overflow-y-auto "
      style="padding-bottom: 50px; margin-top: 10px;"
    >
      <div
        :for={day <- week}
        class={[
          " text-center"
        ]}
      >
        <div :for={meal <- @user_meals}>
          <div class="py-2 rounded-lg">
            <%= for re_u_m <- meal.recipe_user_meals do %>
              <%= if NaiveDateTime.to_date(meal.start_dt) == day do %>
                <.card_meal
                  actual_meal={meal}
                  img_url={re_u_m.img_url}
                  title={re_u_m.title}
                  myself={@myself}
                />
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    <!--Div bodu -->
    """
  end

  def card_meal(assigns) do
    ~H"""
    <div class="bg-slate-700/40 border border-slate-600 rounded-xl p-3 sm:p-4 hover:bg-slate-700/60 transition-colors">
      <div class="flex gap-4 items-center">
        <div class="relative flex-shrink-0 h-20 w-20 sm:h-24 sm:w-24 rounded-xl overflow-hidden">
          <%= if is_nil(@img_url) do %>
            <div class="h-full w-full bg-slate-600 flex items-center justify-center">
              {SvgComponents.get_default_recipe_image(assigns)}
            </div>
          <% else %>
            <img src={@img_url} class="h-full w-full object-cover" />
          <% end %>
          <%= if @actual_meal.id != "landing_id" do %>
            <button
              class="absolute right-1 top-1 bg-slate-900/80 hover:bg-primary-500 text-white p-1 rounded-full transition-colors [&_svg]:size-3.5"
              type="button"
              phx-click="edit_modal"
              phx-value-id={@actual_meal.id}
            >
              {SvgComponents.get_edit_icon(assigns)}
            </button>
          <% end %>
        </div>
        <div class="flex-1 min-w-0">
          <h3 class={"font-semibold text-base leading-snug mb-3 " <> @card_meal_text}>{@title}</h3>
          <div class="flex items-stretch gap-4">
            <div>
              <div class="text-slate-200 text-sm font-medium">{@cooking_portions}</div>
              <div class="text-slate-500 text-xs mt-0.5">prepare</div>
            </div>
            <%= if !is_nil(@consume_portions) do %>
              <div class="w-px bg-slate-600 self-stretch"></div>
              <div>
                <div class="text-slate-200 text-sm font-medium">{@consume_portions}</div>
                <div class="text-slate-500 text-xs mt-0.5">consume</div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def get_class_for_toggle_button(in_stock, calendar_view) do
    if(calendar_view == in_stock) do
      "checked"
    else
      "unchecked"
    end
  end

  defp button_add_meal(assigns) do
    current_date = Date.to_string(assigns.current_date) <> " 00:00:00"
    {:ok, current_date} = NaiveDateTime.from_iso8601(current_date)

    assigns =
      assigns
      |> Map.put(:day, current_date)
      |> Map.put(:meal, "El diablo")

    ~H"""
    <button
      class="absolute right-3 sm:right-4 flex items-center gap-1.5 px-3 py-2 rounded-full bg-primary-500 hover:bg-primary-400 text-white text-xs sm:text-sm font-medium transition-colors shadow-md"
      type="button"
      id="button_calendar"
      phx-target={@myself}
      phx-click="pick-date"
      phx-value-date={Calendar.strftime(@day, "%Y-%m-%d")}
      phx-value-meal={@meal}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="2"
        stroke="currentColor"
        class="size-4 flex-shrink-0"
      >
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
      </svg>
      <span class="hidden sm:inline">Add Meal</span>
    </button>
    """
  end

  @days_el %{1 => "Δευτέρα", 2 => "Τρίτη", 3 => "Τετάρτη", 4 => "Πέμπτη",
             5 => "Παρασκευή", 6 => "Σάββατο", 7 => "Κυριακή"}
  @months_short_el %{1 => "Ιαν", 2 => "Φεβ", 3 => "Μαρ", 4 => "Απρ", 5 => "Μαϊ",
                     6 => "Ιουν", 7 => "Ιουλ", 8 => "Αυγ", 9 => "Σεπ",
                     10 => "Οκτ", 11 => "Νοε", 12 => "Δεκ"}

  defp day_name(%Date{} = date, "el"), do: Map.fetch!(@days_el, Date.day_of_week(date))
  defp day_name(%Date{} = date, _), do: Calendar.strftime(date, "%A")

  defp month_short(%Date{} = date, "el"), do: Map.fetch!(@months_short_el, date.month)
  defp month_short(%Date{} = date, _), do: String.slice(Calendar.strftime(date, "%b"), 0..2)
end
