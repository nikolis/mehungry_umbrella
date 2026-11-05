defmodule MehungryWeb.CalendarLive.Calendar.Editor do
  @moduledoc """
  The nutritionist authoring surface: a week-at-a-glance **grid** (meal-type rows
  × 7 day columns) for laying a client's plan down fast.

  Unlike the consumer `Reader` (today-first reading) and the former stacked-
  accordion widget, every slot is visible at once: each cell shows its meals as
  chips, empty cells show "+ add", and a sticky totals row tracks each day's
  energy/macros against the client's target. In-cell add + chip-edit route to the
  parent `ClientCalendar`'s existing modal flow (`add_cell` / `edit_modal`); week
  nav hands the date to the parent (`{:particular_date, …}`). Past-date columns
  render read-only (the parent also guards writes). Degrades to horizontal scroll
  on narrow screens.
  """
  use MehungryWeb, :live_component

  alias MehungryWeb.CalendarLive.Calendar.Locale
  alias Mehungry.NutrientUtils, as: Nu
  alias Mehungry.History.MealType

  @impl true
  def mount(socket), do: {:ok, assign(socket, :current_language, "en")}

  @impl true
  def update(assigns, socket) do
    current_date =
      case assigns.particular_date do
        nil -> Date.utc_today()
        %Date{} = d -> d
        s when is_binary(s) -> parse_date(s)
      end

    language = Map.get(assigns, :current_language, "en")
    first = Date.beginning_of_week(current_date)
    last = Date.add(first, 6)
    days = Enum.map(0..6, &Date.add(first, &1))
    meals = assigns.user_meals

    has_unsorted = Enum.any?(meals, fn m -> normalize_type(Map.get(m, :meal_type)) == nil end)
    rows = MealType.ordered() ++ if(has_unsorted, do: [nil], else: [])

    {:ok,
     socket
     |> assign(
       current_date: current_date,
       first: first,
       last: last,
       days: days,
       rows: rows,
       cells: group_cells(meals, days, rows),
       day_macros: Map.new(days, fn d -> {d, day_macro(meals, d)} end),
       today: Date.utc_today(),
       calorie_target: Map.get(assigns, :calorie_target),
       device_width: Map.get(assigns, :device_width),
       current_language: language
     )}
  end

  ## ------------------------------------ Render -------------------------------

  @impl true
  def render(assigns) do
    if is_nil(assigns.device_width) do
      MehungryWeb.SvgComponents.get_loading(assigns)
    else
      render_grid(assigns)
    end
  end

  defp render_grid(assigns) do
    assigns =
      assigns
      |> assign(:focus, assigns.current_date)
      |> assign(:focus_macro, assigns.day_macros[assigns.current_date])
      |> assign(:focus_past, past?(assigns.current_date, assigns.today))

    ~H"""
    <div class="bg-ink pb-24">
      <!-- Week navigation -->
      <div class="flex items-center justify-center px-3 py-3">
        <div class="flex items-center gap-3 bg-ink-panel border border-ink-panel2 rounded-full px-3 py-2 shadow-lg">
          <button
            type="button"
            title={gettext("Previous week")}
            aria-label={gettext("Previous week")}
            class="text-parchment-dim hover:text-parchment transition-colors"
            phx-target={@myself}
            phx-click="prev-week"
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="size-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M18.75 19.5 11.25 12l7.5-7.5m-6 15L5.25 12l7.5-7.5" />
            </svg>
          </button>
          <h3 class="text-center text-base font-display font-medium text-parchment [font-variant-numeric:tabular-nums]">
            {gettext("Week of")} {Calendar.strftime(@first, "%d")} {month_short(@first, @current_language)} – {Calendar.strftime(@last, "%d")} {month_short(@last, @current_language)}
          </h3>
          <button
            type="button"
            title={gettext("Next week")}
            aria-label={gettext("Next week")}
            class="text-parchment-dim hover:text-parchment transition-colors"
            phx-target={@myself}
            phx-click="next-week"
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="size-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="m5.25 4.5 7.5 7.5-7.5 7.5m6-15 7.5 7.5-7.5 7.5" />
            </svg>
          </button>
        </div>
      </div>

      <!-- Full week grid (tablet / desktop) -->
      <div class="hidden md:block px-2 sm:px-4 overflow-x-auto">
        <div
          class="min-w-[46rem] grid gap-px bg-ink-panel2 border border-ink-panel2 rounded-xl overflow-hidden"
          style="grid-template-columns: 5.5rem repeat(7, minmax(0, 1fr));"
        >
          <!-- Header row -->
          <div class="bg-ink-panel2"></div>
          <div
            :for={day <- @days}
            class={[
              "bg-ink-panel2 px-1 py-1.5 text-center",
              day == @today && "bg-paprika/20"
            ]}
          >
            <div class="text-[0.6rem] uppercase tracking-wide text-parchment-dim">
              {day_name_short(day, @current_language)}
            </div>
            <div class="text-sm font-bold text-parchment [font-variant-numeric:tabular-nums]">
              {Calendar.strftime(day, "%d")}
            </div>
          </div>

          <!-- Meal-type rows -->
          <%= for type <- @rows do %>
            <div class="bg-ink-panel flex items-center px-2 py-2 text-[0.62rem] uppercase tracking-wide text-parchment-dim">
              {meal_type_label(type, @current_language)}
            </div>
            <.cell
              :for={day <- @days}
              items={@cells[{day, type}]}
              date_str={Calendar.strftime(day, "%Y-%m-%d")}
              type_str={type || ""}
              past={past?(day, @today)}
            />
          <% end %>

          <!-- Totals row -->
          <div class="bg-ink-panel flex items-center px-2 py-2 text-[0.62rem] uppercase tracking-wide text-basil-soft">
            {gettext("Totals")}
          </div>
          <.totals
            :for={day <- @days}
            macro={@day_macros[day]}
            target={@calorie_target}
          />
        </div>
      </div>

      <!-- Focus-day view (phones) -->
      <div class="md:hidden px-3">
        <!-- Day picker -->
        <div class="flex gap-1.5 overflow-x-auto pb-1">
          <button
            :for={day <- @days}
            type="button"
            phx-target={@myself}
            phx-click="focus-day"
            phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
            class={[
              "flex-1 min-w-[2.9rem] rounded-lg border px-1 py-1.5 text-center transition-colors",
              if(day == @focus,
                do: "border-paprika bg-paprika/10",
                else: "border-ink-panel2 bg-ink-panel"
              )
            ]}
          >
            <div class={[
              "text-[0.6rem] uppercase tracking-wide",
              if(day == @focus, do: "text-paprika-soft", else: "text-parchment-dim")
            ]}>
              {day_name_short(day, @current_language)}
            </div>
            <div class="text-sm font-bold text-parchment [font-variant-numeric:tabular-nums] leading-tight">
              {Calendar.strftime(day, "%d")}
            </div>
            <span class={[
              "inline-block w-1 h-1 rounded-full mt-0.5",
              if(@day_macros[day], do: "bg-basil", else: "bg-ink-panel2")
            ]}>
            </span>
          </button>
        </div>

        <!-- Focus day: meal-type sections stacked -->
        <div class="mt-3 space-y-2">
          <div :for={type <- @rows} class="rounded-xl border border-ink-panel2 bg-ink-panel overflow-hidden">
            <div class="flex items-center justify-between gap-2 px-3 py-2 bg-black/20">
              <span class="text-[0.66rem] uppercase tracking-wide text-parchment-dim">
                {meal_type_label(type, @current_language)}
              </span>
              <button
                :if={not @focus_past}
                type="button"
                phx-click="add_cell"
                phx-value-date={Calendar.strftime(@focus, "%Y-%m-%d")}
                phx-value-type={type || ""}
                aria-label={gettext("Add a meal")}
                class="shrink-0 rounded-full px-2.5 py-1 text-paprika-soft hover:text-paprika border border-ink-panel2 hover:border-paprika/40 text-xs transition-colors"
              >
                + {gettext("add")}
              </button>
            </div>
            <div class="p-2 space-y-1.5">
              <%= for item <- @cells[{@focus, type}] do %>
                <%= if @focus_past do %>
                  <span class="block truncate rounded px-2 py-1.5 text-sm bg-ink-panel2/60 text-parchment-dim/70">
                    {item.title}
                  </span>
                <% else %>
                  <button
                    type="button"
                    phx-click="edit_modal"
                    phx-value-id={item.meal_id}
                    class="block w-full text-left truncate rounded px-2 py-1.5 text-sm bg-basil/12 border border-basil/30 text-basil-soft hover:bg-basil/20 transition-colors"
                  >
                    {item.title}
                  </button>
                <% end %>
              <% end %>
              <p :if={@cells[{@focus, type}] == []} class="text-parchment-dim/40 text-xs px-1 py-0.5">
                {gettext("No meals")}
              </p>
            </div>
          </div>
        </div>

        <!-- Focus day totals -->
        <div class="mt-3 rounded-xl border border-ink-panel2 bg-ink-panel px-4 py-3 flex items-center justify-between">
          <span class="text-[0.66rem] uppercase tracking-wide text-basil-soft">{gettext("Day total")}</span>
          <%= if @focus_macro do %>
            <span class="[font-variant-numeric:tabular-nums]">
              <span class={["font-bold", kcal_class(@focus_macro.energy_kcal, @calorie_target)]}>
                {@focus_macro.energy_kcal}
              </span>
              <span :if={@calorie_target} class="text-parchment-dim text-sm">/ {@calorie_target} kcal</span>
              <span class="text-parchment-dim text-xs ml-2">
                P {@focus_macro.protein_g} · C {@focus_macro.carbs_g} · F {@focus_macro.fat_g}
              </span>
            </span>
          <% else %>
            <span class="text-parchment-dim/50 text-sm">{gettext("No meals")}</span>
          <% end %>
        </div>
      </div>

      <p class="hidden md:block px-4 pt-2 text-parchment-dim/60 text-xs">
        {gettext("Tap a cell to add a meal · tap a chip to edit · past days are locked")}
      </p>
    </div>
    """
  end

  # One grid cell: chips for the meals in this (day, meal-type), plus add
  # affordances. Chip/add route to the parent LiveView (no phx-target). Past-date
  # cells are read-only (chips render as plain text, no add).
  attr :items, :list, required: true
  attr :date_str, :string, required: true
  attr :type_str, :string, required: true
  attr :past, :boolean, required: true

  defp cell(assigns) do
    ~H"""
    <div class={["bg-ink p-1 min-h-[3.2rem] flex flex-col gap-1", @past && "bg-black/30"]}>
      <%= for item <- @items do %>
        <%= if @past do %>
          <span class="block truncate rounded px-1.5 py-1 text-[0.72rem] bg-ink-panel2/60 text-parchment-dim/70">
            {item.title}
          </span>
        <% else %>
          <button
            type="button"
            phx-click="edit_modal"
            phx-value-id={item.meal_id}
            title={item.title}
            class="block w-full text-left truncate rounded px-1.5 py-1 text-[0.72rem] bg-basil/12 border border-basil/30 text-basil-soft hover:bg-basil/20 transition-colors"
          >
            {item.title}
          </button>
        <% end %>
      <% end %>
      <%= cond do %>
        <% @past -> %>
          <span :if={@items == []} class="text-parchment-dim/30 text-xs px-1">—</span>
        <% @items == [] -> %>
          <button
            type="button"
            phx-click="add_cell"
            phx-value-date={@date_str}
            phx-value-type={@type_str}
            aria-label={gettext("Add a meal")}
            class="flex-1 min-h-[2.2rem] rounded border border-dashed border-ink-panel2 text-parchment-dim/50 hover:text-paprika-soft hover:border-paprika/40 text-xs transition-colors"
          >
            + {gettext("add")}
          </button>
        <% true -> %>
          <button
            type="button"
            phx-click="add_cell"
            phx-value-date={@date_str}
            phx-value-type={@type_str}
            aria-label={gettext("Add another meal")}
            class="self-start rounded px-1.5 text-parchment-dim/50 hover:text-paprika-soft text-sm leading-none transition-colors"
          >
            +
          </button>
      <% end %>
    </div>
    """
  end

  # A day's totals cell: energy vs the client's target (coloured) + P/C/F.
  attr :macro, :any, required: true
  attr :target, :any, default: nil

  defp totals(assigns) do
    ~H"""
    <div class="bg-ink px-1 py-2 text-center [font-variant-numeric:tabular-nums]">
      <%= if @macro do %>
        <div class={["text-sm font-bold", kcal_class(@macro.energy_kcal, @target)]}>
          {@macro.energy_kcal}<span :if={@target && @macro.energy_kcal > @target * 1.05}>▲</span>
        </div>
        <div class="text-parchment-dim text-[0.58rem]">
          {@macro.protein_g}/{@macro.carbs_g}/{@macro.fat_g}
        </div>
      <% else %>
        <div class="text-parchment-dim/40 text-sm">—</div>
      <% end %>
    </div>
    """
  end

  ## ------------------------------------ Event handlers ------------------------

  @impl true
  def handle_event("prev-week", _, socket),
    do: {:noreply, go_to_week(socket, Date.add(socket.assigns.first, -7))}

  def handle_event("next-week", _, socket),
    do: {:noreply, go_to_week(socket, Date.add(socket.assigns.first, 7))}

  # Mobile day picker: focus a specific day within the viewed week (hands the date
  # to the parent, which reloads that week's meals and re-renders).
  def handle_event("focus-day", %{"date" => date}, socket) do
    send(self(), {:particular_date, %{"date" => date}})
    {:noreply, socket}
  end

  defp go_to_week(socket, %Date{} = day) do
    send(self(), {:particular_date, %{"date" => Date.to_string(Date.beginning_of_week(day))}})
    socket
  end

  ## ------------------------------------ Aggregation ---------------------------

  defp group_cells(meals, days, rows) do
    for day <- days, type <- rows, into: %{} do
      items =
        meals
        |> Enum.filter(fn m ->
          NaiveDateTime.to_date(m.start_dt) == day and normalize_type(Map.get(m, :meal_type)) == type
        end)
        |> Enum.flat_map(&meal_chips/1)

      {{day, type}, items}
    end
  end

  defp meal_chips(meal) do
    Enum.map(meal.recipe_user_meals, &%{meal_id: meal.id, title: &1.title}) ++
      Enum.map(meal.ingredient_user_meals, &%{meal_id: meal.id, title: &1.title}) ++
      Enum.map(Map.get(meal, :free_food_user_meals, []), &%{meal_id: meal.id, title: &1.title})
  end

  defp day_macro(meals, day) do
    case Enum.filter(meals, fn m -> NaiveDateTime.to_date(m.start_dt) == day end) do
      [] -> nil
      ms -> Nu.macro_summary(Nu.summarize_meals_nutrients(ms))
    end
  end

  ## ------------------------------------ Helpers -------------------------------

  defp normalize_type(t) when is_binary(t) do
    if MealType.valid?(t) and t != "", do: t, else: nil
  end

  defp normalize_type(_), do: nil

  defp meal_type_label(nil, _lang), do: gettext("Other")
  defp meal_type_label(type, lang), do: MehungryWeb.MealTypeLabels.label(type, lang)

  defp past?(day, today), do: Date.compare(day, today) == :lt

  # Over target (5% grace) reads paprika; at/under basil; no target → neutral.
  defp kcal_class(_kcal, nil), do: "text-parchment"
  defp kcal_class(kcal, target) when kcal > target * 1.05, do: "text-paprika-soft"
  defp kcal_class(_kcal, _target), do: "text-basil"

  defp parse_date(s) do
    case Date.from_iso8601(s) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  defp day_name_short(%Date{} = date, lang), do: Locale.day_name(date, lang) |> String.slice(0, 3)
  defp month_short(%Date{} = date, lang), do: Locale.month_short(date, lang)
end
