defmodule MehungryWeb.CalendarLive.CalendarWidgetComponent do
  use MehungryWeb, :live_component

  @day_meals ["breakfast", "elevenses", "lunch", "after lunch", "dinner"]
  @impl true
  def render(assigns) do
    case is_nil(assigns.device_width) do
      true ->
        get_loading(assigns)

      false ->
        ~H"""
        <div class="	 " id="calendar_widget" style="margin: auto; max-h-full overflow-scroll ">
          <div>
            <h3 class="text-center text-3xl font-semibold">
              <%= Calendar.strftime(@current_date, "%B %Y") %>
            </h3>
          </div>
          <.calendar_main_table
            week_rows={@week_rows}
            user_meals={@user_meals}
            day_meals={@day_meals}
            current_date={@current_date}
            selected_date={@selected_date}
            myself={@myself}
          />
          <div class="absolute  bottom-0 right-0 left-0 p-2">
            <.calendar_control_buttons myself={@myself} />
          </div>
        </div>
        """
    end
  end

  def calendar_main_table(assigns) do
    ~H"""
    <div style="">
      <div class="">
        <div
          class="border-b-2 border-double border-t-2 border-complementary flex flex-col w-full justify-around"
          style="margin-bottom: 100px;"
        >
          <div class="flex-row flex justify-center	w-full">
            <div :for={week_day <- List.first(@week_rows)} class="contain w-full">
              <!-- th -->
              <div
                class="cursor-pointer relative text-center "
                phx-target{@myself}
                phx-click="date-details"
                phx-value-date={week_day}
              >
                <span class="text-4xl font-normal	text-complementaryd">
                  <%= Calendar.strftime(week_day, "%d") %>
                </span>
                <span class="text-complementaryd text-xl font-normal">
                  <%= Calendar.strftime(week_day, "%a") %>
                </span>
                <.nutrition_widget_button user_meals={@user_meals} week_day={week_day} />
              </div>
            </div>
            <!-- th -->
          </div>
          <div
            :for={week <- @week_rows}
            class="  w-full justify-center overflow-auto	flex flex-row absolute lg:mb-12 bottom-12 lg:bottom-0 xl:bottom-24 "
            style="  top: 100px;"
          >
            <div
              :for={day <- week}
              class={[
                "text-center border-l-2  border-r-2  w-full px-auto"
              ]}
            >
              <div :for={meal <- @day_meals} class="">
                <%= get_from_week_rows(@user_meals, day, meal, assigns) %>
              </div>
            </div>
          </div>
        </div>
      </div>
      <!--Div bodu -->
    </div>
    """
  end

  def calendar_control_buttons(assigns) do
    ~H"""
    <div class="my-auto lg:-mb-0 grid grid-cols-3 justify-between text-xl md:text-3xl 	">
      <button
        type="button"
        class="w-fit text-primary font-medium"
        phx-target={@myself}
        phx-click="prev-month"
      >
        &laquo; Prev
      </button>
      <button class="w-full text-lg">Callendar</button>
      <button
        type="button"
        class="w-full text-end	text-primary font-medium"
        phx-target={@myself}
        phx-click="next-month"
      >
        Next &raquo;
      </button>
    </div>
    """
  end

  def nutrition_widget_button(assigns) do
    ~H"""
    <%= if get_from_week_rows2(@user_meals, @week_day, assigns) > 0 do %>
      <svg
        style="stroke: var(--clr-primary);"
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="1.5"
        stroke="currentColor"
        class="h-8 w-8 absolute right-2 top-0 bottom-0 m-auto"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"
        />
      </svg>
      <!-- <.icon name="hero-information-circle" class="h-5 w-5" style="stroke: white;"/> -->
    <% end %>
    """
  end

  @impl true
  def update(assigns, socket) do
    current_date =
      case assigns.particular_date do
        nil ->
          calculate_initial_date(Date.utc_today(), assigns.device_width)

        date ->
          {:ok, date} = Date.from_iso8601(date)
          date
      end

    {first, last, rows} = week_rows(current_date, assigns.user_meals, assigns.device_width)

    assigns = [
      current_date: current_date,
      selected_date: nil,
      user_meals: assigns.user_meals,
      selected_meal: nil,
      week_rows: rows,
      last: last,
      first: first,
      day_meals: @day_meals,
      device_width: assigns.device_width
    ]

    {:ok,
     socket
     |> assign(assigns)}
  end

  defp calculate_initial_date(current_date, width) do
    days = get_days_according_to_width(width)
    beggining_of_week = Date.beginning_of_week(current_date)

    case days do
      0 ->
        current_date

      1 ->
        current_date

      2 ->
        new_date = Date.add(current_date, -1)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      3 ->
        new_date = Date.add(current_date, -1)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      4 ->
        new_date = Date.add(current_date, -2)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      5 ->
        new_date = Date.add(current_date, -2)

        if(beggining_of_week > new_date) do
          beggining_of_week
        else
          new_date
        end

      6 ->
        beggining_of_week

      _ ->
        beggining_of_week
    end
  end

  @impl true
  def handle_event("prev-month", _, socket) do
    days = get_days_according_to_width(socket.assigns.device_width) * -1
    new_date = socket.assigns.first |> Date.add(days) |> Date.add(-1)

    {first, last, rows} =
      week_rows(new_date, socket.assigns.user_meals, socket.assigns.device_width)

    assigns = [
      current_date: new_date,
      week_rows: rows,
      last: last,
      first: first
    ]

    send(self(), {:particular_date, %{"date" => first}})
    {:noreply, assign(socket, assigns)}
  end

  def handle_event("next-month", _, socket) do
    new_date = socket.assigns.last |> Date.add(1)

    {first, last, rows} =
      week_rows(new_date, socket.assigns.user_meals, socket.assigns.device_width)

    assigns = [
      current_date: new_date,
      week_rows: rows,
      last: last,
      first: first
    ]

    send(self(), {:particular_date, %{"date" => first}})
    {:noreply, assign(socket, assigns)}
  end

  def handle_event("pick-date", %{"date" => date, "meal" => meal}, socket) do
    send(self(), {:initial_modal, %{"date" => date, "title" => meal}})

    {:noreply,
     assign(socket, :selected_date, Date.from_iso8601!(date))
     |> assign(:selected_meal, meal)}
  end

  def handle_event("date-details", %{"date" => date}, socket) do
    send(self(), {:date_details, %{"date" => date}})

    {:noreply, socket}
  end

  defp selected_date?(day, selected_date), do: day == selected_date

  defp today?(day), do: day == Date.utc_today()

  defp other_month?(day, current_date),
    do: Date.beginning_of_month(day) != Date.beginning_of_month(current_date)

  defp get_days_according_to_width(width) do
    case width < 700 do
      true ->
        case width < 400 do
          true ->
            0

          false ->
            1
        end

      false ->
        case width > 700 do
          true ->
            case width > 1000 do
              true ->
                case width > 1300 do
                  true ->
                    case width > 1550 do
                      true ->
                        6

                      false ->
                        5
                    end

                  false ->
                    4
                end

              false ->
                2
            end
        end
    end
  end

  defp week_rows(current_date, _user_meals, device_width) do
    days = get_days_according_to_width(device_width)
    first = current_date
    last = Date.add(first, days)

    week_rows =
      Date.range(first, last)
      |> Enum.map(& &1)
      |> Enum.chunk_every(7)

    {first, last, week_rows}
  end

  defp get_from_week_rows2(user_meals, current_date, _assigns) do
    first = Date.beginning_of_week(current_date)
    last = Date.end_of_week(current_date)

    week_rows =
      Date.range(first, last)
      |> Enum.map(& &1)
      |> Enum.chunk_every(7)

    result = Map.new(week_rows_post_pros23(week_rows, user_meals))
    current_date = Date.to_string(current_date) <> " 00:00:00"

    {:ok, current_date} = NaiveDateTime.from_iso8601(current_date)

    result = Map.get(result, current_date)
    result = Map.values(result)
    result = Enum.filter(result, fn x -> !is_nil(x) end)
    length(result)
  end

  defp get_from_week_rows(user_meals, current_date, title, assigns) do
    first = Date.beginning_of_week(current_date)
    last = Date.end_of_week(current_date)

    week_rows =
      Date.range(first, last)
      |> Enum.map(& &1)
      |> Enum.chunk_every(7)

    result = Map.new(week_rows_post_pros23(week_rows, user_meals))
    current_date = Date.to_string(current_date) <> " 00:00:00"
    {:ok, current_date} = NaiveDateTime.from_iso8601(current_date)
    result = Map.get(result, current_date)
    result = Map.get(result, title)

    assigns =
      assigns
      |> Map.put(:day, current_date)
      |> Map.put(:meal, title)
      |> Map.put(:actual_meal, result)

    week_row_button(assigns)
  end

  defp week_row_button(%{actual_meal: nil} = assigns) do
    ~H"""
    <button
      class={[
        "week_row_button_empty text-center min-h-28 max-h-28 w-full border-t-2 ",
        today?(@day) && "bg-green-100",
        other_month?(@day, @current_date) && "bg-gray-100",
        selected_date?(@day, @selected_date) && @meal == @selected_meal && "bg-blue-100"
      ]}
      type="button"
      phx-target={@myself}
      phx-click="pick-date"
      phx-value-date={Calendar.strftime(@day, "%Y-%m-%d")}
      phx-value-meal={@meal}
    >
      <time datetime={Calendar.strftime(@day, "%Y-%m-%d")}>
        <span class="text-md capitalize text-complementaryd font-semibold"><%= @meal %></span>
      </time>
    </button>
    """
  end

  defp week_row_button(assigns) do
    ~H"""
    <button
      class={[
        "week_row_button  text-center min-h-28 max-h-28  w-full bg-primaryl3 border-t-2 overflow-hidden overflow-y-auto",
        today?(@day) && "bg-green-100",
        other_month?(@day, @current_date) && "bg-gray-100",
        selected_date?(@day, @selected_date) && @meal == @selected_meal && "bg-blue-100"
      ]}
      type="button"
      phx-click="edit_modal"
      phx-value-id={@actual_meal.id}
    >
      <div class="capitalize text-complementaryd font-medium  overflow-hidden">
        <div class="font-semibold text-md"><%= @actual_meal.title %></div>
        <div :for={meal <- @actual_meal.recipe_user_meals}>
          <div class="text-sm"><%= meal.title %></div>
        </div>
      </div>
    </button>
    """
  end

  defp get_loading(assigns) do
    ~H"""
    <div style="max-width: 60vh; margin: auto;">
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200">
        <radialGradient
          id="a12"
          cx=".66"
          fx=".66"
          cy=".3125"
          fy=".3125"
          gradientTransform="scale(1.5)"
        >
          <stop offset="0" stop-color="#00A0D0"></stop>
          <stop offset=".3" stop-color="#00A0D0" stop-opacity=".9"></stop>
          <stop offset=".6" stop-color="#00A0D0" stop-opacity=".6"></stop>
          <stop offset=".8" stop-color="#00A0D0" stop-opacity=".3"></stop>
          <stop offset="1" stop-color="#00A0D0" stop-opacity="0"></stop>
        </radialGradient>
        <circle
          transform-origin="center"
          fill="none"
          stroke="url(#a12)"
          stroke-width="15"
          stroke-linecap="round"
          stroke-dasharray="200 1000"
          stroke-dashoffset="0"
          cx="100"
          cy="100"
          r="70"
        >
          <animateTransform
            type="rotate"
            attributeName="transform"
            calcMode="spline"
            dur="2"
            values="360;0"
            keyTimes="0;1"
            keySplines="0 0 1 1"
            repeatCount="indefinite"
          >
          </animateTransform>
        </circle>
        <circle
          transform-origin="center"
          fill="none"
          opacity=".2"
          stroke="#FF156D"
          stroke-width="15"
          stroke-linecap="round"
          cx="100"
          cy="100"
          r="70"
        >
        </circle>
      </svg>
    </div>
    """
  end

  defp get_from_user_meals(user_meals, date, title) do
    result = Enum.filter(user_meals, fn x -> x.start_dt == date and x.title == title end)

    case result do
      [] ->
        nil

      [result] ->
        result
    end
  end

  defp week_rows_post_pros23(week_rows, user_meals) do
    week_rows_tr = List.first(week_rows)

    translated_week_rows =
      Enum.map(week_rows_tr, fn x -> Date.to_string(x) <> " 00:00:00" end)
      |> Enum.map(fn y -> NaiveDateTime.from_iso8601(y) end)
      |> Enum.map(fn {:ok, date} ->
        {date,
         Enum.map(@day_meals, fn x ->
           meal = get_from_user_meals(user_meals, date, x)
           {x, meal}
         end)
         |> Map.new()}
      end)

    translated_week_rows
  end
end
