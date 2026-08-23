defmodule MehungryWeb.CalendarLive.Calendar.Widget do
  use MehungryWeb, :live_component

  alias MehungryWeb.SvgComponents
  alias MehungryWeb.CalendarLive.Calendar.Locale

  alias Mehungry.NutrientUtils, as: Nu
  alias Mehungry.History.MealType

  # Public entry (used by `LandingLive` with raw meals): filters + aggregates,
  # then renders. The widget itself renders from a per-day summary precomputed
  # once in `update/2` via `render_day_chart/4` so it doesn't re-aggregate on
  # every LiveView update.
  def get_chart(user_meals, day, current_date, calorie_target \\ nil) do
    meals = Enum.filter(user_meals, fn x -> NaiveDateTime.to_date(x.start_dt) == day end)

    case meals do
      [] ->
        nil

      _ ->
        render_day_chart(
          %{meals: meals, total_nutrients: Nu.summarize_meals_nutrients(meals)},
          day,
          current_date,
          calorie_target
        )
    end
  end

  # Renders a day's summary card from an already-aggregated summary
  # (`%{meals: _, total_nutrients: _}`). Returns nil for a day with no meals.
  defp render_day_chart(nil, _day, _current_date, _calorie_target), do: nil
  defp render_day_chart(%{total_nutrients: nil}, _day, _current_date, _calorie_target), do: nil

  defp render_day_chart(
         %{meals: meals, total_nutrients: total_nutrients},
         day,
         current_date,
         calorie_target
       ) do
    total_nutrients
    |> summary_assigns(meals, "day-#{Date.to_string(day)}", calorie_target)
    # Folded by default like each meal-type section — tap the header (which shows
    # the day's totals) to reveal the Nutrition Facts + charts. On the current day
    # the totals also sit on the day's accordion header, so drop the redundant row.
    |> Map.merge(%{
      title: "Daily Summary",
      subtitle: nil,
      foldable: true,
      show_tags: day != current_date
    })
    |> summary_card()
  end

  # Renders one meal-type section's summary card from an already-aggregated
  # per-type summary (`%{meal_type, label, meals, total_nutrients}`). The
  # `id_key` is suffixed with the type slug so its charts/DOM ids never collide
  # with the overall daily/weekly cards. Meals in the unsorted bucket carry a
  # nil meal_type, so fall back to the "unsorted" slug for a stable key.
  defp render_meal_type_chart(%{total_nutrients: nil}, _day, _calorie_target), do: nil

  defp render_meal_type_chart(
         %{meal_type: meal_type, label: label, meals: meals, total_nutrients: total_nutrients},
         day,
         calorie_target
       ) do
    type_slug = meal_type || "unsorted"

    total_nutrients
    |> summary_assigns(meals, "day-#{Date.to_string(day)}-#{type_slug}", calorie_target)
    |> Map.merge(%{
      title: "#{label} Summary",
      subtitle: nil,
      foldable: false,
      # The badges already show on the section's accordion header, so keep the
      # inner nutrition card to just the facts table + charts.
      show_tags: false
    })
    |> summary_card()
  end

  # Weekly summary rendered once, below the day accordions. Shows the *daily
  # average* consumption over the week: the week's total nutrients divided by the
  # number of days in the range, then run through the same summary card as the
  # per-day chart. The meal/item counts stay as week totals for context.
  # Renders from a summary precomputed in `update/2`.
  defp render_week_chart(nil, _first, _days, _calorie_target), do: nil

  defp render_week_chart(
         %{meals: meals, total_nutrients: total_nutrients},
         first,
         days,
         calorie_target
       ) do
    total_nutrients
    |> summary_assigns(meals, "week-#{Date.to_string(first)}", calorie_target)
    |> Map.merge(%{
      title: "Weekly Summary",
      subtitle: "Daily average over #{days} days",
      foldable: true,
      show_tags: true
    })
    |> summary_card()
  end

  # Builds the shared assigns for a summary card from an already-aggregated
  # nutrient map. `id_key` disambiguates the chart/live_component DOM ids between
  # the daily and weekly cards.
  defp summary_assigns(total_nutrients, meals, id_key, calorie_target) do
    nutrients_sorted = Mehungry.Food.RecipeUtils.sort_nutrients_from_db(total_nutrients)

    # Two separate pies: macros (grams) and micronutrients (mg/µg). They can't
    # share one chart because the units live on different scales — a slice is
    # only meaningful against others in the same unit. Within each pie we still
    # convert every value to grams so the arc angles reflect real proportions.
    macro_data = build_macro_slices(total_nutrients)
    micro_data = build_slices(nutrients_sorted, &(not Nu.macronutrient?(&1)))

    recipe = %{
      nutrients: total_nutrients,
      id: "overview_#{id_key}",
      primary_size: 5
    }

    summary_metrics(total_nutrients, meals, calorie_target)
    |> Map.merge(%{
      recipe: recipe,
      macro_data: macro_data,
      micro_data: micro_data,
      id_key: id_key
    })
  end

  # Scalar badge metrics (counts + energy/macros) shared by the summary card
  # header and each day's accordion header. `total_nutrients` is the aggregated
  # `name => nutrient` map from `Nu.summarize_meals_nutrients/1`.
  defp summary_metrics(total_nutrients, meals, calorie_target) do
    macros = Nu.macro_totals(total_nutrients)
    amount = fn bucket -> macros |> Map.get(bucket, %{}) |> Map.get("amount", 0) end

    total_items =
      Enum.sum(
        Enum.map(meals, fn m ->
          length(m.recipe_user_meals) + length(m.ingredient_user_meals)
        end)
      )

    %{
      meal_count: length(meals),
      total_items: total_items,
      energy_kcal: energy_amount(total_nutrients) |> round(),
      calorie_target: calorie_target,
      protein_g: amount.(:protein) |> to_number() |> Float.round(1),
      fat_g: amount.(:fat) |> to_number() |> Float.round(1),
      carbs_g: amount.(:carbs) |> to_number() |> Float.round(1),
      sugars_g: amount.(:sugars) |> to_number() |> Float.round(1),
      fiber_g: amount.(:fiber) |> to_number() |> Float.round(1)
    }
  end

  # Energy isn't a macro bucket, so pull it out separately by canonical name.
  defp energy_amount(total_nutrients) do
    case Enum.find(total_nutrients, fn {label, _} -> String.contains?(label, "Energy") end) do
      {_label, %{"amount" => a}} when is_number(a) -> a * 1.0
      _ -> 0.0
    end
  end

  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(_), do: 0.0

  # Colour the actual kcal relative to the target: paprika when over, basil when
  # at/under. A 5% grace band keeps small overages from reading as "over".
  defp target_kcal_class(actual, target) when is_number(actual) and is_number(target) do
    if actual > target * 1.05, do: "text-paprika", else: "text-basil"
  end

  defp target_kcal_class(_actual, _target), do: "text-basil"

  # Scales every nutrient amount by `1 / divisor` (e.g. week total → daily
  # average), preserving the map shape the summary card expects.
  defp scale_nutrients(total_nutrients, divisor) when divisor > 0 do
    Map.new(total_nutrients, fn
      {label, %{"amount" => amount} = nutrient} when is_number(amount) ->
        {label, Map.put(nutrient, "amount", amount / divisor)}

      {label, nutrient} ->
        {label, nutrient}
    end)
  end

  # The nutrient badge row (meals · items, kcal, protein, carbs, fat) shared by
  # the summary-card headers and each day's accordion header.
  def summary_tags(assigns) do
    ~H"""
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@meal_count}</span>
      meal{if @meal_count != 1, do: "s"} ·
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@total_items}</span>
      item{if @total_items != 1, do: "s"}
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 font-bold [font-variant-numeric:tabular-nums] text-xs">
      <%= if @calorie_target do %>
        <span class={target_kcal_class(@energy_kcal, @calorie_target)}>{@energy_kcal}</span>
        <span class="text-parchment-dim">/ {@calorie_target} kcal</span>
      <% else %>
        <span class="text-basil">{@energy_kcal} kcal</span>
      <% end %>
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@protein_g}</span>g protein
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@fat_g}</span>g fat
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@carbs_g}</span>g carbs
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@sugars_g}</span>g sugars
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@fiber_g}</span>g fiber
    </span>
    """
  end

  # Per-day nutrient tags for the accordion header. Renders nothing when the day
  # has no meals (the collapsed body already shows the empty state). Reads the
  # day's summary precomputed in `update/2` rather than re-aggregating.
  def day_header_tags(assigns) do
    assigns = assign_new(assigns, :calorie_target, fn -> nil end)

    metrics =
      case assigns.summary do
        %{total_nutrients: tn, meals: meals} when not is_nil(tn) ->
          summary_metrics(tn, meals, assigns.calorie_target)

        _ ->
          nil
      end

    assigns = assign(assigns, :metrics, metrics)

    ~H"""
    <div :if={@metrics} class="ml-auto flex flex-wrap gap-2 items-center justify-start">
      <.summary_tags {@metrics} />
    </div>
    """
  end

  def summary_card(assigns) do
    ~H"""
    <div class="mt-2 rounded-xl border border-ink-panel2 overflow-hidden bg-ink-panel">
      <div
        class={[
          "flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3 bg-black/20 border-b border-ink-panel2",
          @foldable && "cursor-pointer select-none"
        ]}
        phx-click={
          @foldable &&
            Phoenix.LiveView.JS.toggle(
              to: "#summary-body-" <> @id_key,
              in:
                {"transition-all duration-300 ease-out", "opacity-0 -translate-y-2",
                 "opacity-100 translate-y-0"},
              out:
                {"transition-all duration-200 ease-in", "opacity-100 translate-y-0",
                 "opacity-0 -translate-y-2"}
            )
            |> Phoenix.LiveView.JS.toggle_class("rotate-180", to: "#summary-chevron-" <> @id_key)
        }
      >
        <div class="flex flex-col">
          <span class="font-display font-medium text-parchment text-sm">{@title}</span>
          <%= if @subtitle do %>
            <span class="text-parchment-dim/70 text-xs">{@subtitle}</span>
          <% end %>
        </div>
        <div :if={@show_tags} class="flex flex-wrap gap-2 ml-auto md:pr-8">
          <.summary_tags
            meal_count={@meal_count}
            total_items={@total_items}
            energy_kcal={@energy_kcal}
            calorie_target={@calorie_target}
            protein_g={@protein_g}
            fat_g={@fat_g}
            carbs_g={@carbs_g}
            sugars_g={@sugars_g}
            fiber_g={@fiber_g}
          />
        </div>
        <%= if @foldable do %>
          <div class="w-full relative">
            <svg
              id={"summary-chevron-" <> @id_key}
              class="w-6 h-6 ml-2 text-parchment-dim transition-transform duration-300 ease-out flex-shrink-0 absolute right-0 bottom-0"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 9l-7 7-7-7"
              />
            </svg>
          </div>
        <% end %>
      </div>
      <div
        id={"summary-body-" <> @id_key}
        class={["flex flex-col sm:flex-row min-h-0", @foldable && "hidden"]}
      >
        <div
          class="flex-1 sm:border-r border-b sm:border-b-0 border-ink-panel2 overflow-y-auto"
          style="max-height: 400px;"
        >
          {MehungryWeb.RecipeComponents.recipe_nutrients(@recipe)}
        </div>
        <div class="flex-1 flex flex-col sm:flex-row items-stretch justify-center gap-2 p-4 sm:p-6">
          <div class="flex-1 flex flex-col items-center">
            <span class="font-display font-medium text-parchment-dim text-xs uppercase tracking-wide mb-1">
              Macros
            </span>
            <%= if @macro_data == [] do %>
              <p class="text-parchment-dim/70 text-xs italic my-auto">No macro data</p>
            <% else %>
              <.live_component
                module={MehungryWeb.CalendarLive.Calendar.PieChart}
                id={"macro-chart-" <> @id_key}
                data={@macro_data}
                origin_id={"macro-chart-" <> @id_key}
                size="20rem"
              />
            <% end %>
          </div>
          <div class="flex-1 flex flex-col items-center">
            <span class="font-display font-medium text-parchment-dim text-xs uppercase tracking-wide mb-1">
              Micronutrients
            </span>
            <%= if @micro_data == [] do %>
              <p class="text-parchment-dim/70 text-xs italic my-auto">No micronutrient data</p>
            <% else %>
              <.live_component
                module={MehungryWeb.CalendarLive.Calendar.PieChart}
                id={"micro-chart-" <> @id_key}
                data={@micro_data}
                origin_id={"micro-chart-" <> @id_key}
                size="20rem"
              />
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    case is_nil(assigns.device_width) do
      true ->
        SvgComponents.get_loading(assigns)

      false ->
        ~H"""
        <div class="bg-ink pb-20" id="calendar_widget">
          <div class="relative flex items-center px-3 py-3 sm:px-4">
            <.button_add_meal current_date={@current_date} myself={@myself} />

            <div class="flex px-3 py-2 gap-3 bg-ink-panel justify-center border border-ink-panel2 rounded-full mx-auto w-fit shadow-lg">
              <button
                type="button"
                class="w-fit text-parchment-dim hover:text-parchment transition-colors"
                phx-target={@myself}
                phx-click="prev-day"
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

              <h3 class="text-center text-lg font-display font-medium text-parchment">
                <span>{day_name(@current_date, assigns[:current_language] || "en")},</span>
                <span>{String.slice(Calendar.strftime(@current_date, "%d"), 0..2)}</span>
                <span>{month_short(@current_date, assigns[:current_language] || "en")}</span>
              </h3>

              <button
                type="button"
                class="w-fit text-end text-parchment-dim hover:text-parchment transition-colors font-medium"
                phx-target={@myself}
                phx-click="next-day"
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
            day_summaries={@day_summaries}
            week_summary={@week_summary}
            days_in_week={@days_in_week}
            current_date={@current_date}
            selected_date={@selected_date}
            myself={@myself}
            current_language={@current_language}
            calorie_target={@calorie_target}
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
          Date.utc_today()

        date ->
          {:ok, date} = Date.from_iso8601(date)
          date
      end

    {first, last, rows} = get_full_week(current_date)
    language = Map.get(assigns, :current_language, "en")

    # calorie_target is resolved once in the parent LiveView's mount and passed
    # in, so this component doesn't hit the DB for the profile on every re-render.
    calorie_target = Map.get(assigns, :calorie_target)

    # Aggregate each day's (and the week's) nutrients once here instead of inside
    # the render functions, which used to re-summarize on every LiveView update
    # (and re-summarize the current day twice — for its header tags and chart).
    days_in_week = Date.diff(last, first) + 1
    day_summaries = build_day_summaries(assigns.user_meals, first, last)
    week_summary = build_week_summary(assigns.user_meals, first, last, days_in_week)

    assigns = [
      current_date: current_date,
      selected_date: nil,
      user_meals: assigns.user_meals,
      selected_meal: nil,
      week_rows: rows,
      last: last,
      first: first,
      calendar_view: assigns.calendar_view,
      device_width: assigns.device_width,
      current_language: language,
      calorie_target: calorie_target,
      day_summaries: day_summaries,
      week_summary: week_summary,
      days_in_week: days_in_week
    ]

    {:ok,
     socket
     |> assign(assigns)}
  end

  ## ------------------------------------ Utility Functions  ---------------------------------------------------------------

  # Builds the macros pie from the aggregated `name => nutrient` map. Each of the
  # five macro buckets contributes at most one slice (`Nu.macro_totals/1` already
  # collapsed the messy USDA name variants). Carbs are shown *net* — carbs minus
  # sugars minus fiber (both are subsets of total carbs) — so the three slices
  # don't double-count and the arc angles add up honestly.
  @macro_slice_labels %{
    protein: "Protein",
    fat: "Total Fat",
    carbs: "Net Carbs",
    sugars: "Total Sugars",
    fiber: "Fiber"
  }

  defp build_macro_slices(total_nutrients) do
    macros = Nu.macro_totals(total_nutrients)

    grams =
      Map.new(macros, fn {bucket, nutrient} ->
        case Nu.to_grams(to_number(nutrient["amount"]), nutrient["measurement_unit"] || "") do
          {:ok, g} -> {bucket, g}
          :error -> {bucket, nil}
        end
      end)

    net_subtract = (grams[:sugars] || 0.0) + (grams[:fiber] || 0.0)

    Enum.flat_map([:protein, :fat, :carbs, :sugars, :fiber], fn bucket ->
      grams_value =
        case {bucket, grams[bucket]} do
          {_, nil} -> nil
          {:carbs, g} -> max(g - net_subtract, 0.0)
          {_, g} -> g
        end

      if is_number(grams_value) and grams_value > 0 do
        [
          %{
            category: @macro_slice_labels[bucket],
            value: Float.round(grams_value, 6),
            display: "#{Float.round(grams_value, 1)} g"
          }
        ]
      else
        []
      end
    end)
  end

  # Builds the pie-slice list for one chart: keeps nutrients matching `keep?`,
  # drops Energy and the mixed-unit "Vitamins" umbrella, converts each remaining
  # value to grams (so proportions are honest) and keeps the original amount+unit
  # for the tooltip. Capped at 6 slices so the pie stays readable.
  defp build_slices(nutrients_sorted, keep?) do
    nutrients_sorted
    |> Enum.reject(fn {{label, _}, _} ->
      String.contains?(label, "Energy") or String.contains?(label, "Vitamins")
    end)
    |> Enum.filter(fn {{label, _}, _} -> keep?.(label) end)
    |> Enum.flat_map(fn {{label, nutrient}, _} ->
      amount = nutrient["amount"]
      unit = nutrient["measurement_unit"]

      case Nu.to_grams(amount, unit) do
        {:ok, grams} when grams > 0 ->
          [
            %{
              category: clean_label(label),
              value: Float.round(grams, 6),
              display: "#{amount} #{unit}"
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.take(6)
  end

  defp clean_label(label) do
    label
    |> String.replace("\n", " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  # Precomputes a `date => %{meals, total_nutrients, type_summaries}` map for
  # every day in the visible week. `total_nutrients` is nil for days with no
  # meals; `type_summaries` is the ordered per-meal-type breakdown (see
  # `build_meal_type_summaries/1`). Aggregating here (once per update) keeps the
  # render functions from re-summarizing on every LiveView update.
  defp build_day_summaries(user_meals, first, last) do
    Map.new(Date.range(first, last), fn day ->
      meals = Enum.filter(user_meals, fn m -> NaiveDateTime.to_date(m.start_dt) == day end)

      total_nutrients =
        case meals do
          [] -> nil
          _ -> Nu.summarize_meals_nutrients(meals)
        end

      {day,
       %{
         meals: meals,
         total_nutrients: total_nutrients,
         type_summaries: build_meal_type_summaries(meals)
       }}
    end)
  end

  # Groups a day's meals by `meal_type` and aggregates nutrients per group,
  # returning an ordered list (`MealType.ordered()` then the nil/unsorted bucket
  # last). Empty groups are dropped so only populated meal-type sections render.
  # Uses `Map.get/2` defensively since synthetic meals (LandingLive) may omit the
  # key — those paths don't call this, but it keeps grouping total.
  defp build_meal_type_summaries(meals) do
    by_type = Enum.group_by(meals, fn m -> Map.get(m, :meal_type) end)

    for meal_type <- MealType.ordered() ++ [nil],
        group = by_type[meal_type],
        group not in [nil, []] do
      %{
        meal_type: meal_type,
        label: MealType.label(meal_type),
        meals: group,
        total_nutrients: Nu.summarize_meals_nutrients(group)
      }
    end
  end

  # Precomputes the weekly summary (daily-average nutrients over the range), or
  # nil when the week has no meals.
  defp build_week_summary(user_meals, first, last, days_in_week) do
    meals =
      Enum.filter(user_meals, fn m ->
        d = NaiveDateTime.to_date(m.start_dt)
        Date.compare(d, first) != :lt and Date.compare(d, last) != :gt
      end)

    case meals do
      [] ->
        nil

      _ ->
        total_nutrients =
          meals
          |> Nu.summarize_meals_nutrients()
          |> scale_nutrients(days_in_week)

        %{meals: meals, total_nutrients: total_nutrients}
    end
  end

  defp get_full_week(current_date) do
    days = 6
    first = Date.beginning_of_week(current_date)

    last = Date.add(first, days)

    week_rows =
      Date.range(first, last)
      |> Enum.map(& &1)
      |> Enum.chunk_every(7)

    {first, last, week_rows}
  end

  ## ------------------------------------ Event Handlers  ---------------------------------------------------------------

  @impl true
  def handle_event("prev-day", _, socket) do
    new_date = Date.add(socket.assigns.current_date, -1)

    {first, last, rows} = get_full_week(new_date)

    assigns = [
      current_date: new_date,
      week_rows: rows,
      last: last,
      first: first
    ]

    send(self(), {:particular_date, %{"date" => new_date}})
    {:noreply, assign(socket, assigns)}
  end

  def handle_event("next-day", _, socket) do
    new_date = Date.add(socket.assigns.current_date, 1)

    {first, last, rows} = get_full_week(new_date)

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
          class="bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden day_of_week"
          id={"dat_" <> Date.to_string(day)}
        >
          <div class="flex flex-wrap items-center gap-2 px-3 py-3 sm:px-4 bg-black/20 border-b border-ink-panel2">
            <span
              class="flex items-center gap-2 text-parchment font-semibold text-sm sm:text-base cursor-pointer hover:text-parchment-dim transition-colors"
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
                class="size-4 text-parchment-dim flex-shrink-0"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 9v6m3-3H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
                />
              </svg>
              {day_name(day, assigns[:current_language] || "en")}
            </span>
            <span class="text-parchment-dim text-xs sm:text-sm">
              {Calendar.strftime(day, "%d")} {month_short(day, assigns[:current_language] || "en")}
            </span>
            <.day_header_tags
              :if={day == @current_date}
              summary={@day_summaries[day]}
              calorie_target={@calorie_target}
            />
            <span
              class="ml-auto text-parchment-dim hover:text-parchment transition-colors cursor-pointer p-1"
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
            <% day_meals = @day_summaries[day].meals %>
            <%= if day_meals == [] do %>
              <div class="flex flex-col items-center gap-3 py-8 px-4">
                <div class="w-14 h-14 rounded-full bg-ink-panel2/60 border border-ink-panel2/50 flex items-center justify-center">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.2"
                    stroke="currentColor"
                    class="size-7 text-parchment-dim"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M12 8.25v-1.5m0 1.5c-1.355 0-2.697.056-4.024.166C6.845 8.51 6 9.473 6 10.608v2.513m6-4.871c1.355 0 2.697.056 4.024.166C17.155 8.51 18 9.473 18 10.608v2.513M15 8.25v-1.5m-6 1.5v-1.5m12 9.75-1.5.75a3.354 3.354 0 0 1-3 0 3.354 3.354 0 0 0-3 0 3.354 3.354 0 0 1-3 0 3.354 3.354 0 0 0-3 0 3.354 3.354 0 0 1-1.5-.75M3 13.5l1.5.75a3.354 3.354 0 0 0 3 0 3.354 3.354 0 0 1 3 0 3.354 3.354 0 0 0 3 0 3.354 3.354 0 0 1 3 0 3.354 3.354 0 0 0 1.5-.75M3 13.5v6.75a.75.75 0 0 0 .75.75h16.5a.75.75 0 0 0 .75-.75V13.5"
                    />
                  </svg>
                </div>
                <div class="text-center">
                  <p class="text-parchment-dim text-sm font-medium">No meals planned</p>
                  <p class="text-parchment-dim/70 text-xs mt-0.5">
                    Tap <span class="text-paprika-soft font-semibold">+</span> to add one
                  </p>
                </div>
              </div>
            <% else %>
              <div class="p-2 sm:p-3 space-y-6">
                <%!-- Meals grouped by type (breakfast … dinner, unsorted last), each
                      with its own nutrition summary; the combined Daily Summary
                      follows all sections. Groups are already day-scoped in
                      `build_day_summaries`, so no per-card date guard is needed. --%>
                <%= for group <- @day_summaries[day].type_summaries do %>
                  <% type_slug = group.meal_type || "unsorted" %>
                  <% section_key = "meal-type-#{Date.to_string(day)}-#{type_slug}" %>
                  <% metrics = summary_metrics(group.total_nutrients, group.meals, @calorie_target) %>
                  <%!-- Each meal type is its own accordion: the header button shows the
                        label + summary badges; the cards and nutrition breakdown live in a
                        body that stays hidden until the header is tapped. --%>
                  <section class="rounded-xl border border-ink-panel2 overflow-hidden bg-ink-panel/60">
                    <button
                      type="button"
                      class="w-full flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2.5 bg-black/20 hover:bg-black/30 transition-colors text-left cursor-pointer select-none"
                      phx-click={
                        Phoenix.LiveView.JS.toggle(
                          to: "#" <> section_key <> "-body",
                          in:
                            {"transition-all duration-300 ease-out", "opacity-0 -translate-y-2",
                             "opacity-100 translate-y-0"},
                          out:
                            {"transition-all duration-200 ease-in", "opacity-100 translate-y-0",
                             "opacity-0 -translate-y-2"}
                        )
                        |> Phoenix.LiveView.JS.toggle_class("rotate-180",
                          to: "#" <> section_key <> "-chevron"
                        )
                      }
                    >
                      <span class="font-display font-medium text-parchment text-sm">
                        {group.label}
                      </span>
                      <div class="flex flex-wrap gap-2 items-center ml-auto">
                        <.summary_tags {metrics} />
                        <svg
                          id={section_key <> "-chevron"}
                          class="w-5 h-5 text-parchment-dim transition-transform duration-300 ease-out flex-shrink-0"
                          fill="none"
                          stroke="currentColor"
                          viewBox="0 0 24 24"
                        >
                          <path
                            stroke-linecap="round"
                            stroke-linejoin="round"
                            stroke-width="2"
                            d="M19 9l-7 7-7-7"
                          />
                        </svg>
                      </div>
                    </button>
                    <div id={section_key <> "-body"} class="hidden p-2 sm:p-3 space-y-2">
                      <%= for meal <- group.meals do %>
                        <%= for re_u_m <- meal.recipe_user_meals do %>
                          <.card_meal
                            card_meal_text="text-parchment"
                            actual_meal={meal}
                            img_url={re_u_m.img_url}
                            title={re_u_m.title}
                            nutrients={re_u_m.recipe_nutrients}
                            cooking_portions={re_u_m.cooking_portions}
                            consume_portions={re_u_m.consume_portions}
                            myself={@myself}
                            recipe_id={re_u_m.recipe_id}
                            recipe={
                              %{
                                nutrients: re_u_m.recipe_nutrients,
                                primary_size: re_u_m.primary_size,
                                servings: re_u_m.servings,
                                id: "#{re_u_m.recipe_id}-#{meal.id}"
                              }
                            }
                          />
                        <% end %>
                        <%= for re_u_m <- meal.ingredient_user_meals do %>
                          <.card_meal
                            card_meal_text="text-parchment"
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
                                id: "#{re_u_m.recipe.id}-#{meal.id}"
                              }
                            }
                          />
                        <% end %>
                      <% end %>
                      {render_meal_type_chart(group, day, @calorie_target)}
                    </div>
                  </section>
                <% end %>
                {render_day_chart(@day_summaries[day], day, @current_date, @calorie_target)}
              </div>
            <% end %>
          </div>
        </div>
      </div>

      <div class="mt-4 mb-2">
        {render_week_chart(@week_summary, @first, @days_in_week, @calorie_target)}
      </div>
    </div>
    """
  end

  def card_meal(assigns) do
    # `recipe_id` is the numeric recipe id for recipe cards (nil for ingredient
    # cards); it gates the "View recipe" button that opens the details modal.
    assigns = assign_new(assigns, :recipe_id, fn -> nil end)

    ~H"""
    <div class="bg-black/20 border border-ink-panel2 rounded-xl p-3 sm:p-4 hover:bg-black/30 transition-colors">
      <div class="flex gap-4 items-center">
        <div class="relative flex-shrink-0 h-20 w-20 sm:h-24 sm:w-24 rounded-xl overflow-hidden">
          <%= if is_nil(@img_url) do %>
            <div class="h-full w-full bg-ink-panel2 flex items-center justify-center">
              {SvgComponents.get_default_recipe_image(assigns)}
            </div>
          <% else %>
            <img src={@img_url} class="h-full w-full object-cover" />
          <% end %>
          <%= if @actual_meal.id != "landing_id" do %>
            <button
              class="absolute right-1 top-1 bg-ink/80 hover:bg-ink-panel2 text-parchment p-1 rounded-full transition-colors [&_svg]:size-3.5"
              type="button"
              phx-click="edit_modal"
              phx-value-id={@actual_meal.id}
            >
              {SvgComponents.get_edit_icon(assigns)}
            </button>
          <% end %>
        </div>
        <div class="flex-1 min-w-0">
          <h3 class={"font-display font-medium text-base leading-snug mb-3 " <> @card_meal_text}>
            {@title}
          </h3>
          <div class="flex items-stretch gap-4">
            <div>
              <div class="text-basil font-bold [font-variant-numeric:tabular-nums] text-sm">
                {@cooking_portions}
              </div>
              <div class="text-parchment-dim text-xs mt-0.5">prepare</div>
            </div>
            <%= if !is_nil(@consume_portions) do %>
              <div class="w-px bg-ink-panel2 self-stretch"></div>
              <div>
                <div class="text-basil font-bold [font-variant-numeric:tabular-nums] text-sm">
                  {@consume_portions}
                </div>
                <div class="text-parchment-dim text-xs mt-0.5">consume</div>
              </div>
            <% end %>
          </div>
          <%= if @recipe_id do %>
            <button
              type="button"
              phx-click="show_recipe_details"
              phx-value-recipe_id={@recipe_id}
              class="mt-3 inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-basil/40 text-xs font-medium transition-colors"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-3.5 flex-shrink-0"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
                />
              </svg>
              View recipe
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
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
      class="absolute right-3 sm:right-4 flex items-center gap-1.5 px-3 py-2 rounded-full bg-paprika hover:bg-paprika-soft text-ink text-xs sm:text-sm font-bold transition-colors shadow-md"
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

  # Locale-aware day/month names live in `Calendar.Locale` (single source for
  # i18n). These thin wrappers keep the template call sites terse.
  defp day_name(%Date{} = date, lang), do: Locale.day_name(date, lang)
  defp month_short(%Date{} = date, lang), do: Locale.month_short(date, lang)
end
