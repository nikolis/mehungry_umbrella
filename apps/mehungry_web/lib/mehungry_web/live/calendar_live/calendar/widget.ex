defmodule MehungryWeb.CalendarLive.Calendar.Widget do
  use MehungryWeb, :live_component

  alias MehungryWeb.CalendarLive.Calendar.Utils
  alias MehungryWeb.SvgComponents

  @day_meals ["breakfast", "elevenses", "lunch", "after lunch", "dinner"]
  @impl true
  def render(assigns) do
    case is_nil(assigns.device_width) do
      true ->
        SvgComponents.get_loading(assigns)

      false ->
        ~H"""
        <div class="h-full" id="calendar_widget">
          <div class="w-full relative">
            <.button_add_meal current_date={@current_date} myself={@myself} />
            <.button_settings myself={@myself} calendar_view={@calendar_view} />

            <div class="flex px-4 py-2 gap-4 bg-greyfriend1 justify-center border-2 rounded-full border-greyfriend3 	m-auto w-fit">
              <button
                type="button"
                class="w-fit text-complementary font-medium"
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

              <h3 class="text-center text-lg font-semibold ">
                <span><%= Calendar.strftime(@current_date, "%A") %>,</span>
                <span><%= String.slice(Calendar.strftime(@current_date, "%d"), 0..2) %></span>
                <span><%= String.slice(Calendar.strftime(@current_date, "%B"), 0..2) %></span>
              </h3>

              <button
                type="button"
                class="w-fit text-end text-complementary font-medium"
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
            <!-- Flex Container closed -->
          </div>
          <%= if @calendar_view == "day_view" do %>
            <.table_day_calendar
              week_rows={@week_rows}
              user_meals={@user_meals}
              day_meals={@day_meals}
              current_date={@current_date}
              selected_date={@selected_date}
              myself={@myself}
            />
          <% else %>
            <.table_week_calendar
              week_rows={@week_rows}
              first={@first}
              last={@last}
              user_meals={@user_meals}
              day_meals={@day_meals}
              current_date={@current_date}
              selected_date={@selected_date}
              myself={@myself}
            />
          <% end %>
        </div>
        """
    end
  end

  def table_week_calendar(assigns) do
    # user_meals =
    # Enum.filter(assigns.user_meals, fn x ->
    #  NaiveDateTime.to_date(x.start_dt) == assigns.current_date
    # end)

    # assigns = Map.put(assigns, :user_meals, user_meals)
    # first_of_week = Date.beginning_of_week(assigns.current_date)
    # assigns = Map.put(assigns, :first_of_week, first_of_week)

    ~H"""
    <div
      :for={week <- @week_rows}
      class="h-full overflow-y-auto "
      style="padding-bottom: 50px; margin-top: 10px;"
    >
      <div
        :for={day <- week}
        class={[
          "text-center  overflow-hidden "
        ]}
      >
        <div
          class="w-full mt-2 border-t-2 border-greyfriend2 day_of_week relative "
          id={"dat_" <> Date.to_string(day) }
        >
          <div class="p-2 mt-2">
            <%= for meal <- Enum.filter(@user_meals, fn x -> NaiveDateTime.to_date(x.start_dt) == day end) do %>
              <div class="py-6 rounded-lg">
                <%= for re_u_m <- meal.recipe_user_meals do %>
                  <%= if NaiveDateTime.to_date(meal.start_dt) == day do %>
                    <.card_meal actual_meal={meal} img_url={re_u_m.img_url} title={re_u_m.title} />
                  <% else %>
                    nil
                  <% end %>
                <% end %>
              </div>
            <% end %>
          </div>

          <span
            phx-target={@myself}
            phx-click="pick-date"
            phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
            class="absolute  text-lg top-4   left-12 font-semibold cursor-pointer "
          >
            <%= Calendar.strftime(day, "%A") %>
          </span>

          <span
            class="absolute top-4   left-4 font-semibold"
            phx-target={@myself}
            phx-click="pick-date"
            phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
          >
            <div class="flex">
              <span class="">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="1.5"
                  stroke="currentColor"
                  class="size-7"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M12 9v6m3-3H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                  />
                </svg>
              </span>
            </div>
          </span>
          <span
            class="absolute top-4  right-4  font-semibold"
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
              class="size-6 widget_day cursor-pointer"
              id={"widget"<> Date.to_string(day)}
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
            </svg>
          </span>
        </div>
      </div>
    </div>
    <!--Div bodu -->
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
                <.card_meal actual_meal={meal} img_url={re_u_m.img_url} title={re_u_m.title} />
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    <!--Div bodu -->
    """
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
      device_width: assigns.device_width
    ]

    {:ok,
     socket
     |> assign(assigns)}
  end

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
    # days = Utils.get_days_according_to_width(device_width)
    # days = 0
    # first = current_date
    # last = Date.add(first, days)

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

  defp card_meal(assigns) do
    ~H"""
    <div class="shadow m-auto w-full  grid-cols-6 grid rounded-md relative">
      <button
        class="absolute bg-white right-1 top-1"
        type="button"
        phx-click="edit_modal"
        phx-value-id={@actual_meal.id}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="size-6"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10"
          />
        </svg>
      </button>
      <%= if is_nil(@img_url) do %>
        <%= SvgComponents.get_default_recipe_image(assigns) %>
      <% else %>
        <img src={@img_url} class="col-span-2 h-full" />
      <% end %>
      <div class="col-span-4 px-6 py-4"><%= @title %></div>
    </div>
    """
  end

  defp button_settings(assigns) do
    ~H"""
    <div class="absolute top-0 bottom-0 left-0 h-fit m-auto">
      <label for="tw-settings-modal" class=" h-full m-auto ">
        <div class=" h-fit m-auto top-0 w-fit flex ">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="1.5"
            stroke="currentColor"
            class="size-8"
            style="color: var(--clr-complementary-middle)"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M6 13.5V3.75m0 9.75a1.5 1.5 0 0 1 0 3m0-3a1.5 1.5 0 0 0 0 3m0 3.75V16.5m12-3V3.75m0 9.75a1.5 1.5 0 0 1 0 3m0-3a1.5 1.5 0 0 0 0 3m0 3.75V16.5m-6-9V3.75m0 3.75a1.5 1.5 0 0 1 0 3m0-3a1.5 1.5 0 0 0 0 3m0 9.75V10.5"
            />
          </svg>
        </div>
      </label>
      <input
        tabindex="-1"
        type="checkbox"
        phx-change="other"
        id="tw-settings-modal"
        }
        class="peer fixed appearance-none opacity-0 hidden"
      />
      <!-- modal -->
      <label
        for="tw-settings-modal"
        class="z-40 pointer-events-none invisible fixed inset-0 flex cursor-pointer items-center justify-center overflow-hidden overscroll-contain bg-slate-700/30 opacity-0 transition-all duration-200 ease-in-out peer-checked:pointer-events-auto peer-checked:visible peer-checked:opacity-100 peer-checked: [&>*]:translate-y-0 peer-checked:[&>*]:scale-100"
      >
        <!-- modal box -->
        <label class="max-h-[calc(100vh -5 em)] h-5/6 sm:h-4/6 md:h-3/6 mx-4 w-full  max-w-lg scale-90 overflow-y-auto overscroll-contain rounded-md bg-white p-6 text-black shadow-2xl transition ">
          <div class="fixed  top-0 bottom-0 right-0 left-0 bg-white p-6" style="">
            <!--- modal content -->
            <h3 class="p-2 text-center">Caledar Settings</h3>
            <!-- modal  content -->

             <!--Setting checkbox  -->
            <div class=" flex gap-2">
              <button
                phx-click="toggle_basket"
                class={"checkbox " <> get_class_for_toggle_button("day_view", @calendar_view)}
                phx-value-view="day_view"
              >
                Cla
              </button>
              <div style="margin-top: 0.9rem; border-bottom: 1px solid var(--clr-grey-friend_3);">
                Daily View
              </div>
            </div>
            <!--Setting checkbox  -->
              <!--Setting checkbox  -->
            <div class=" flex gap-2">
              <button
                phx-click="toggle_basket"
                class={"checkbox " <> get_class_for_toggle_button("week_view", @calendar_view)}
                phx-value-view="week_view"
              >
                Cla
              </button>
              <div style="margin-top: 0.9rem; border-bottom: 1px solid var(--clr-grey-friend_3);">
                Weekly View
              </div>
            </div>
            <!--Setting checkbox  -->
          </div>
        </label>
      </label>
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
      class={[
        "text-center w-fit absolute right-0 top-0 bottom-0 "
      ]}
      type="button"
      id="button_calendar"
      phx-target={@myself}
      phx-click="pick-date"
      phx-value-date={Calendar.strftime(@day, "%Y-%m-%d")}
      phx-value-meal={@meal}
    >
      <div class=" h-fit m-auto top-0 w-fit flex ">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="size-8"
          style="color: var(--clr-primary) "
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 9v6m3-3H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
          />
        </svg>
      </div>
    </button>
    """
  end
end
