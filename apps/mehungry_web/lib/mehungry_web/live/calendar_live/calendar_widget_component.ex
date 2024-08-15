defmodule MehungryWeb.CalendarLive.CalendarWidgetComponent do
  use MehungryWeb, :live_component

  @week_start_at :monday
  @day_meals ["breakfast", "elevenses", "lunch", "after lunch" , "dinner"]
  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-44 mt-12">
      <div>
      <h3 class="text-center"><%= Calendar.strftime(@current_date, "%B %Y") %></h3>
   </div>
      <table>
        <thead>
          <tr>
            <th :for={week_day <- List.first(@week_rows)}>
              <div> <span class="text-3xl	"> <%= Calendar.strftime(week_day, "%d") %> </span>  
                    <span> <%= Calendar.strftime(week_day, "%a") %> </span> 
              </div>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr :for={week <- @week_rows}>
            <td :for={day <- week} class={[
              "text-center",
              ]}
            >
              <div :for={meal <- @day_meals} >
              <button   class={[
              "text-center min-h-24 w-full border-solid border-2 border-sky-500",
              today?(day) && "bg-green-100",
              other_month?(day, @current_date)  && "bg-gray-100",
              selected_date?(day, @selected_date) &&  meal==@selected_meal && "bg-blue-100"
              ]} 
    
    type="button" phx-click="initial_modal" phx-value-date={Calendar.strftime(day, "%Y-%m-%d")} phx-value-title={meal} >
                  <time datetime={Calendar.strftime(day, "%Y-%m-%d")}><%= meal %></time>
                </button>
              </div>
              <!--<button type="button" phx-target={@myself} phx-click="pick-date" phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}>
                <time datetime={Calendar.strftime(day, "%Y-%m-%d")}><%= Calendar.strftime(day, "%d") %></time>
              </button> -->
            </td>
          </tr>
        </tbody>
        </table>
      <div class="grid grid-cols-3 justify-between text-3xl		">
      <button type="button" class="w-fit" phx-target={@myself} phx-click="prev-month">&laquo; Prev</button>
      <button class="w-full text-lg"> Callendar </button>
      <button type="button" class="w-full text-end	" phx-target={@myself} phx-click="next-month">Next &raquo;</button>
      </div>
 
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    current_date = Date.utc_today()
    IO.inspect(assigns.user_meals, label: "User meals")
    assigns = [
      current_date: current_date,
      selected_date: nil,
      selected_meal: nil,
      week_rows: week_rows(current_date, assigns.user_meals),
      day_meals: @day_meals
    ]

    {:ok,
     socket
     |> assign(assigns)
    }
  end

  def handle_event("prev-month", _, socket) do
    new_date = socket.assigns.current_date |> Date.beginning_of_week() |> Date.add(-1)

    assigns = [
      current_date: new_date,
      week_rows: week_rows(new_date, socket.assigns.user_meals)
    ]

    {:noreply, assign(socket, assigns)}
  end

  def handle_event("next-month", _, socket) do
    new_date = socket.assigns.current_date |> Date.end_of_week() |> Date.add(1)
    assigns = [
      current_date: new_date,
      week_rows: week_rows(new_date, socket.assigns.user_meals)
    ]

    {:noreply, assign(socket, assigns)}
  end
  
  defp selected_date?(day, selected_date), do: day == selected_date

  defp today?(day), do: day == Date.utc_today()

  defp other_month?(day, current_date), do: Date.beginning_of_month(day) != Date.beginning_of_month(current_date)
  
  def handle_event("pick-date", %{"date" => date, "meal" => meal}, socket) do
    {:noreply, 
      assign(socket, :selected_date, Date.from_iso8601!(date))
      |> assign(:selected_meal, meal)
    }
  end
  
  defp week_rows(current_date, user_meals) do
    first = Date.beginning_of_week(current_date)
    last = Date.end_of_week(current_date)

    week_rows = 
    Date.range(first, last)
    |> Enum.map(& &1)
    |> Enum.chunk_every(7)

    week_rows_post_pros(week_rows, user_meals)
  end

  defp week_rows_post_pros(week_rows, user_meals) do
    IO.inspect(week_rows)
    week_rows_tr = List.first(week_rows)
    translated_week_rows = 
      Enum.map(week_rows_tr, fn x -> Date.to_string(x) <> " 00:00:00" end)
      |> Enum.map( fn y -> NaiveDateTime.from_iso8601(y) end)
      |> Enum.map(fn {:ok, date} -> date end )
    IO.inspect(user_meals)
    IO.inspect(translated_week_rows)
    week_rows
  end

end 
