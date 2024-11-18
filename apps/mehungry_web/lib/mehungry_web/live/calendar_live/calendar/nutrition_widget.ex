defmodule MehungryLive.CalendarLive.Calendar.NutritionWidget do
  use MehungryWeb, :live_component

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
        class="h-8 w-8 absolute top-0 bottom-0 m-auto"
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

  defp week_rows_post_pros23(week_rows, user_meals) do
    week_rows_tr = List.first(week_rows)

    translated_week_rows =
      Enum.map(week_rows_tr, fn x -> Date.to_string(x) <> " 00:00:00" end)
      |> Enum.map(fn y -> NaiveDateTime.from_iso8601(y) end)
      |> Enum.map(fn {:ok, date} ->
        {date,
         Enum.map(user_meals, fn x ->
           meal = get_from_user_meals(user_meals, date, "Test234")
           {x, meal}
         end)
         |> Map.new()}
      end)

    translated_week_rows
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
end
