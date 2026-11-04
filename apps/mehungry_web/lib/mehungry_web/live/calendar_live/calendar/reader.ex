defmodule MehungryWeb.CalendarLive.Calendar.Reader do
  @moduledoc """
  The consumer-facing meal-planner surface: a today-first *reader*.

  The Reader is optimised for *reading* the plan (the nutritionist's authoring
  grid is `Calendar.Editor`): it opens on the focus day (today by default), shows
  an always-on "on track" status band, lays each meal-type group out flat (no
  nested accordion), and renders the rest of the week as compact rows that expand
  inline. It reuses the shared meal view-model (`History.format_user_meals/2`),
  the nutrient aggregation in `Mehungry.NutrientUtils`, and the card / tag /
  day-note function components in `Calendar.MealCore` — only the information
  architecture is new.

  Navigation + per-day add route to the parent `CalendarLive.Index` the same way
  the Widget does (`{:particular_date, …}` / `{:initial_modal, …}`), so no new
  parent handlers are needed.
  """
  use MehungryWeb, :live_component

  alias MehungryWeb.SvgComponents
  alias MehungryWeb.BlueprintComponents
  alias MehungryWeb.CalendarLive.Calendar.Locale
  alias MehungryWeb.CalendarLive.Calendar.MealCore
  alias Mehungry.NutrientUtils, as: Nu
  alias Mehungry.History.MealType
  alias Mehungry.AI.Agents.MealPlanAgent

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :current_language, "en")}
  end

  @impl true
  def update(assigns, socket) do
    current_date =
      case assigns.particular_date do
        nil -> Date.utc_today()
        %Date{} = d -> d
        date when is_binary(date) -> parse_date(date)
      end

    language = Map.get(assigns, :current_language, "en")
    {first, last} = week_bounds(current_date)
    days = Date.range(first, last) |> Enum.to_list()
    days_in_week = Date.diff(last, first) + 1

    day_summaries = build_day_summaries(assigns.user_meals, days, language)
    week_summary = build_week_summary(assigns.user_meals, first, last, days_in_week)

    {:ok,
     socket
     |> assign(
       current_date: current_date,
       user_meals: assigns.user_meals,
       first: first,
       last: last,
       days: days,
       days_in_week: days_in_week,
       day_summaries: day_summaries,
       week_summary: week_summary,
       calorie_target: Map.get(assigns, :calorie_target),
       avoid_terms: Map.get(assigns, :avoid_terms, []),
       day_notes: Map.get(assigns, :day_notes),
       active_blueprint: Map.get(assigns, :active_blueprint),
       blueprint_progress: Map.get(assigns, :blueprint_progress),
       device_width: Map.get(assigns, :device_width),
       current_language: language
     )}
  end

  ## ------------------------------------ Render -------------------------------

  @impl true
  def render(assigns) do
    if is_nil(assigns.device_width) do
      SvgComponents.get_loading(assigns)
    else
      render_reader(assigns)
    end
  end

  defp render_reader(assigns) do
    focus = assigns.current_date
    assigns = assign(assigns, :focus, focus)
    assigns = assign(assigns, :focus_summary, assigns.day_summaries[focus])
    assigns = assign(assigns, :other_days, Enum.reject(assigns.days, &(&1 == focus)))

    # When following a blueprint, the focus day's Goals/Avoid coverage is shown
    # under the status band (the reader has no per-day header to carry it).
    focus_progress =
      if assigns.active_blueprint && assigns.blueprint_progress,
        do: day_progress(assigns.blueprint_progress, focus),
        else: nil

    assigns = assign(assigns, :focus_progress, focus_progress)

    ~H"""
    <div class="bg-ink pb-24" id="calendar_reader">
      <!-- Week navigation -->
      <div class="flex items-center justify-center px-3 py-3 sm:px-4">
        <div class="flex items-center gap-1.5 sm:gap-3 bg-ink-panel border border-ink-panel2 rounded-full px-2.5 sm:px-3 py-2 shadow-lg max-w-full">
          <.nav_btn label={gettext("Previous week")} event="prev-week" myself={@myself}>
            <path stroke-linecap="round" stroke-linejoin="round" d="M18.75 19.5 11.25 12l7.5-7.5m-6 15L5.25 12l7.5-7.5" />
          </.nav_btn>
          <.nav_btn label={gettext("Previous day")} event="prev-day" myself={@myself}>
            <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
          </.nav_btn>
          <h3 class="flex-1 min-w-0 text-center text-sm sm:text-lg font-display font-medium text-parchment whitespace-nowrap truncate px-1">
            {day_name(@focus, @current_language)}, {Calendar.strftime(@focus, "%d")} {month_short(@focus, @current_language)}
          </h3>
          <.nav_btn label={gettext("Next day")} event="next-day" myself={@myself}>
            <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
          </.nav_btn>
          <.nav_btn label={gettext("Next week")} event="next-week" myself={@myself}>
            <path stroke-linecap="round" stroke-linejoin="round" d="m5.25 4.5 7.5 7.5-7.5 7.5m6-15 7.5 7.5-7.5 7.5" />
          </.nav_btn>
        </div>
      </div>

      <!-- Week strip: meal count + on-target dot per day -->
      <div class="px-3 sm:px-4">
        <div class="flex gap-1.5 overflow-x-auto pb-1">
          <button
            :for={day <- @days}
            type="button"
            phx-target={@myself}
            phx-click="focus-day"
            phx-value-date={Calendar.strftime(day, "%Y-%m-%d")}
            aria-current={day == @focus && "true"}
            class={[
              "flex-1 min-w-[2.9rem] rounded-lg border px-1 py-1.5 text-center transition-colors",
              if(day == @focus,
                do: "border-paprika bg-paprika/10",
                else: "border-ink-panel2 bg-ink-panel hover:border-paprika/40"
              )
            ]}
          >
            <div class={[
              "text-[0.6rem] uppercase tracking-wide",
              if(day == @focus, do: "text-paprika-soft", else: "text-parchment-dim")
            ]}>
              {day_name_short(day, @current_language)}
            </div>
            <div class="text-base font-bold [font-variant-numeric:tabular-nums] text-parchment leading-tight">
              {meal_count(@day_summaries[day])}
            </div>
            <span class={["inline-block w-1.5 h-1.5 rounded-full mt-0.5", dot_class(@day_summaries[day], @calorie_target)]}></span>
          </button>
        </div>
      </div>

      <!-- Focus-day status band -->
      <div class="px-3 sm:px-4 pt-3">
        <.status_band
          date={@focus}
          summary={@focus_summary}
          calorie_target={@calorie_target}
          avoid_terms={@avoid_terms}
          current_language={@current_language}
        />
        <div :if={@focus_progress} class="flex flex-wrap gap-2 items-center mt-2">
          <span :if={@focus_progress.required != []} class="text-parchment-dim text-xs">Goals:</span>
          <BlueprintComponents.goal_chips entries={@focus_progress.required} />
          <span :if={@focus_progress.avoid != []} class="text-parchment-dim text-xs ml-1">Avoid:</span>
          <BlueprintComponents.avoid_chips entries={@focus_progress.avoid} />
        </div>
      </div>

      <!-- Focus-day meals, flat -->
      <div class="px-3 sm:px-4 pt-3">
        <%= if empty_day?(@focus_summary) do %>
          <.empty_day myself={@myself} day={@focus} />
        <% else %>
          <.day_meal_groups
            summary={@focus_summary}
            avoid_terms={@avoid_terms}
            myself={@myself}
            current_language={@current_language}
          />
          <div class="mt-3">
            <.add_meal_button day={@focus} myself={@myself} current_language={@current_language} />
          </div>
        <% end %>
        <MealCore.day_note_form :if={@day_notes} day={@focus} body={Map.get(@day_notes, @focus)} />
      </div>

      <!-- Rest of the week: compact, expandable rows -->
      <div class="px-3 sm:px-4 pt-5">
        <p class="text-parchment-dim/70 text-[0.68rem] uppercase tracking-wide mb-2">
          {gettext("Rest of the week")}
        </p>
        <div class="space-y-2">
          <div :for={day <- @other_days} class="rounded-xl border border-ink-panel2 bg-ink-panel overflow-hidden" id={"row_" <> Date.to_string(day)}>
            <button
              type="button"
              aria-expanded="false"
              aria-controls={"rowbody-" <> Date.to_string(day)}
              class="w-full flex items-center gap-2 px-3 py-2.5 bg-black/20 text-left cursor-pointer select-none"
              phx-click={
                Phoenix.LiveView.JS.toggle(to: "#rowbody-" <> Date.to_string(day))
                |> Phoenix.LiveView.JS.toggle_class("rotate-180", to: "#rowchev-" <> Date.to_string(day))
                |> Phoenix.LiveView.JS.toggle_attribute({"aria-expanded", "true", "false"})
              }
            >
              <span class="font-semibold text-parchment text-sm">{day_name(day, @current_language)}</span>
              <span class="text-parchment-dim text-xs">{Calendar.strftime(day, "%d")} {month_short(day, @current_language)}</span>
              <span class="ml-auto flex items-center gap-2">
                <.row_badge summary={@day_summaries[day]} calorie_target={@calorie_target} />
                <svg
                  id={"rowchev-" <> Date.to_string(day)}
                  class="w-4 h-4 text-parchment-dim transition-transform duration-300 flex-shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </span>
            </button>
            <div id={"rowbody-" <> Date.to_string(day)} class="hidden p-2 sm:p-3">
              <%= if empty_day?(@day_summaries[day]) do %>
                <div class="flex items-center justify-between gap-3 px-2 py-3">
                  <span class="text-parchment-dim/70 text-xs italic">{gettext("No meals planned")}</span>
                  <.add_meal_button day={day} myself={@myself} current_language={@current_language} compact />
                </div>
              <% else %>
                <.day_meal_groups
                  summary={@day_summaries[day]}
                  avoid_terms={@avoid_terms}
                  myself={@myself}
                  current_language={@current_language}
                />
                <div class="mt-2">
                  <.add_meal_button day={day} myself={@myself} current_language={@current_language} compact />
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- Weekly average footer -->
      <div :if={@week_summary} class="px-3 sm:px-4 pt-5">
        <div class="rounded-xl border border-ink-panel2 bg-ink-panel px-4 py-3 flex flex-wrap items-center gap-2">
          <div class="flex flex-col">
            <span class="font-display font-medium text-parchment text-sm">{gettext("Weekly average")}</span>
            <span class="text-parchment-dim/70 text-xs">
              {gettext("Daily average over %{days} days", days: @days_in_week)}
            </span>
          </div>
          <div class="flex flex-wrap gap-2 ml-auto">
            <MealCore.summary_tags
              meal_count={@week_summary.meal_count}
              total_items={@week_summary.total_items}
              energy_kcal={@week_summary.macro.energy_kcal}
              calorie_target={@calorie_target}
              protein_g={@week_summary.macro.protein_g}
              fat_g={@week_summary.macro.fat_g}
              carbs_g={@week_summary.macro.carbs_g}
              sugars_g={@week_summary.macro.sugars_g}
              fiber_g={@week_summary.macro.fiber_g}
              sodium_mg={@week_summary.macro.sodium_mg}
              saturated_fat_g={@week_summary.macro.saturated_fat_g}
            />
          </div>
          <.link
            patch={~p"/calendar/details/#{Date.to_string(@first)}"}
            class="w-full text-paprika-soft hover:text-paprika text-xs font-medium mt-1"
          >
            {gettext("View full nutrition detail")} →
          </.link>
        </div>
      </div>
    </div>
    """
  end

  ## ------------------------------------ Function components -------------------

  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :myself, :any, required: true
  slot :inner_block, required: true

  defp nav_btn(assigns) do
    ~H"""
    <button
      type="button"
      title={@label}
      aria-label={@label}
      class="shrink-0 text-parchment-dim hover:text-parchment transition-colors"
      phx-target={@myself}
      phx-click={@event}
    >
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor" class="size-5">
        {render_slot(@inner_block)}
      </svg>
    </button>
    """
  end

  # The always-on "on track" band for the focus day: energy vs target, the macro
  # line, an explicit on-track/over state (text + icon, never colour alone), and a
  # count of flagged avoid-foods. A "nutrition detail" link opens the existing
  # per-day nutrition modal.
  attr :date, :any, required: true
  attr :summary, :any, required: true
  attr :calorie_target, :any, default: nil
  attr :avoid_terms, :list, default: []
  attr :current_language, :string, default: "en"

  defp status_band(assigns) do
    macro = assigns.summary && assigns.summary.macro
    assigns = assign(assigns, :macro, macro)
    assigns = assign(assigns, :flagged, flagged_count(assigns.summary, assigns.avoid_terms))

    ~H"""
    <div class="rounded-xl border border-ink-panel2 bg-gradient-to-b from-basil/10 to-transparent px-4 py-3 flex flex-wrap items-center gap-x-4 gap-y-1.5">
      <span class="font-display font-medium text-parchment text-base">
        {today_label(@date)} · {day_name(@date, @current_language)} {Calendar.strftime(@date, "%d")}
      </span>
      <%= if @macro do %>
        <span class="font-bold [font-variant-numeric:tabular-nums]">
          <span class={kcal_text_class(@macro.energy_kcal, @calorie_target)}>{@macro.energy_kcal}</span>
          <%= if @calorie_target do %>
            <span class="text-parchment-dim font-medium">/ {@calorie_target} kcal</span>
          <% else %>
            <span class="text-parchment-dim font-medium">kcal</span>
          <% end %>
        </span>
        <span class="text-parchment-dim text-xs [font-variant-numeric:tabular-nums]">
          P {@macro.protein_g} · C {@macro.carbs_g} · F {@macro.fat_g}
        </span>
        <.ontrack_pill kcal={@macro.energy_kcal} target={@calorie_target} />
        <span :if={@flagged > 0} class="inline-flex items-center gap-1 text-amber-300 text-xs font-semibold">
          <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01M4.93 4.93l14.14 14.14M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          {ngettext("%{count} avoid-flag", "%{count} avoid-flags", @flagged, count: @flagged)}
        </span>
        <.link
          patch={~p"/calendar/details/#{Calendar.strftime(@date, "%Y-%m-%d")}"}
          class="ml-auto text-paprika-soft hover:text-paprika text-xs font-medium"
        >
          {gettext("Nutrition detail")} →
        </.link>
      <% else %>
        <span class="text-parchment-dim/70 text-sm italic">{gettext("No meals planned yet")}</span>
      <% end %>
    </div>
    """
  end

  attr :kcal, :integer, required: true
  attr :target, :any, required: true

  defp ontrack_pill(assigns) do
    ~H"""
    <%= cond do %>
      <% is_nil(@target) -> %>
        <span></span>
      <% @kcal > @target * 1.05 -> %>
        <span class="inline-flex items-center gap-1 text-paprika-soft text-xs font-semibold">
          ▲ {@kcal - @target} {gettext("over")}
        </span>
      <% true -> %>
        <span class="inline-flex items-center gap-1 text-basil text-xs font-semibold">
          ✓ {gettext("on track")}
        </span>
    <% end %>
    """
  end

  # A day's flat meal-type groups: a lightweight label over its cards (no nested
  # accordion). Reuses `MealCore.card_meal/1` for every item type.
  attr :summary, :any, required: true
  attr :avoid_terms, :list, default: []
  attr :myself, :any, required: true
  attr :current_language, :string, default: "en"

  defp day_meal_groups(assigns) do
    ~H"""
    <div class="space-y-4">
      <div :for={group <- @summary.type_summaries}>
        <p class="text-parchment-dim text-[0.66rem] uppercase tracking-wide mb-1.5 flex items-center gap-2">
          <span>{group.label}</span>
          <span class="flex-1 h-px bg-ink-panel2"></span>
        </p>
        <div class="space-y-2">
          <%= for meal <- group.meals do %>
            <MealCore.card_meal
              :for={re_u_m <- meal.recipe_user_meals}
              card_meal_text="text-parchment"
              actual_meal={meal}
              avoid_terms={@avoid_terms}
              img_url={re_u_m.img_url}
              title={re_u_m.title}
              nutrients={re_u_m.recipe_nutrients}
              cooking_portions={re_u_m.cooking_portions}
              consume_portions={re_u_m.consume_portions}
              myself={@myself}
              recipe_id={re_u_m.recipe_id}
              recipe={%{
                nutrients: re_u_m.recipe_nutrients,
                primary_size: re_u_m.primary_size,
                servings: re_u_m.servings,
                id: "#{re_u_m.recipe_id}-#{meal.id}"
              }}
            />
            <MealCore.card_meal
              :for={re_u_m <- meal.ingredient_user_meals}
              card_meal_text="text-parchment"
              myself={@myself}
              actual_meal={meal}
              avoid_terms={@avoid_terms}
              img_url={re_u_m.img_url}
              icon={re_u_m.icon}
              title={re_u_m.title}
              cooking_portions={re_u_m.portions}
              consume_portions={nil}
              recipe={%{
                nutrients: re_u_m.recipe.nutrients,
                primary_size: re_u_m.primary_size,
                servings: re_u_m.portions,
                id: "#{re_u_m.recipe.id}-#{meal.id}"
              }}
            />
            <MealCore.card_meal
              :for={ff_m <- Map.get(meal, :free_food_user_meals, [])}
              card_meal_text="text-parchment"
              myself={@myself}
              actual_meal={meal}
              avoid_terms={@avoid_terms}
              img_url={ff_m.img_url}
              title={ff_m.title}
              cooking_portions={"#{round(ff_m.grams)} g"}
              consume_portions={nil}
              recipe={%{
                nutrients: ff_m.recipe.nutrients,
                primary_size: ff_m.primary_size,
                servings: nil,
                id: "freefood-#{ff_m.id}-#{meal.id}"
              }}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :day, :any, required: true
  attr :myself, :any, required: true
  attr :current_language, :string, default: "en"
  attr :compact, :boolean, default: false

  defp add_meal_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-target={@myself}
      phx-click="pick-date"
      phx-value-date={Calendar.strftime(@day, "%Y-%m-%d")}
      aria-label={gettext("Add a meal on %{day}", day: day_name(@day, @current_language))}
      class={[
        "inline-flex items-center gap-1.5 rounded-full font-bold transition-colors",
        if(@compact,
          do: "px-3 py-1.5 border border-ink-panel2 text-paprika-soft hover:border-paprika/50 text-xs",
          else: "px-4 py-2 bg-paprika hover:bg-paprika-soft text-ink text-sm"
        )
      ]}
    >
      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="size-4">
        <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
      </svg>
      {gettext("Add a meal")}
    </button>
    """
  end

  attr :myself, :any, required: true
  attr :day, :any, required: true

  defp empty_day(assigns) do
    ~H"""
    <div class="flex flex-col items-center gap-3 py-8">
      <div class="w-14 h-14 rounded-full bg-ink-panel2/60 border border-ink-panel2/50 flex items-center justify-center">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.2" stroke="currentColor" class="size-7 text-parchment-dim">
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 8.25v-1.5m0 1.5c-1.355 0-2.697.056-4.024.166C6.845 8.51 6 9.473 6 10.608v2.513m6-4.871c1.355 0 2.697.056 4.024.166C17.155 8.51 18 9.473 18 10.608v2.513M15 8.25v-1.5m-6 1.5v-1.5m12 9.75-1.5.75a3.354 3.354 0 0 1-3 0 3.354 3.354 0 0 0-3 0 3.354 3.354 0 0 1-3 0 3.354 3.354 0 0 0-3 0 3.354 3.354 0 0 1-1.5-.75M3 13.5l1.5.75a3.354 3.354 0 0 0 3 0 3.354 3.354 0 0 1 3 0 3.354 3.354 0 0 0 3 0 3.354 3.354 0 0 1 3 0 3.354 3.354 0 0 0 1.5-.75M3 13.5v6.75a.75.75 0 0 0 .75.75h16.5a.75.75 0 0 0 .75-.75V13.5" />
        </svg>
      </div>
      <p class="text-parchment-dim text-sm font-medium">{gettext("No meals planned")}</p>
      <.add_meal_button day={@day} myself={@myself} />
    </div>
    """
  end

  attr :summary, :any, required: true
  attr :calorie_target, :any, default: nil

  defp row_badge(assigns) do
    ~H"""
    <%= if @summary && @summary.macro do %>
      <span class="px-2 py-0.5 rounded-full bg-ink-panel2 text-xs [font-variant-numeric:tabular-nums]">
        <span class="text-basil font-bold">{@summary.meal_count}</span>
        <span class="text-parchment-dim">{ngettext("meal", "meals", @summary.meal_count)}</span>
      </span>
      <span class={["px-2 py-0.5 rounded-full bg-ink-panel2 text-xs font-bold [font-variant-numeric:tabular-nums]", kcal_text_class(@summary.macro.energy_kcal, @calorie_target)]}>
        {@summary.macro.energy_kcal} kcal
      </span>
    <% else %>
      <span class="text-parchment-dim/60 text-xs italic">{gettext("empty")}</span>
    <% end %>
    """
  end

  ## ------------------------------------ Event handlers ------------------------

  @impl true
  def handle_event("prev-day", _, socket),
    do: {:noreply, go_to(socket, Date.add(socket.assigns.current_date, -1))}

  def handle_event("next-day", _, socket),
    do: {:noreply, go_to(socket, Date.add(socket.assigns.current_date, 1))}

  def handle_event("prev-week", _, socket),
    do: {:noreply, go_to(socket, beginning_of_week(Date.add(socket.assigns.current_date, -7)))}

  def handle_event("next-week", _, socket),
    do: {:noreply, go_to(socket, beginning_of_week(Date.add(socket.assigns.current_date, 7)))}

  def handle_event("focus-day", %{"date" => date}, socket),
    do: {:noreply, go_to(socket, parse_date(date))}

  # Per-day add: same contract the Widget uses — the parent opens the add-meal
  # modal pre-set to this day.
  def handle_event("pick-date", %{"date" => date}, socket) do
    send(self(), {:initial_modal, %{"date" => date, "title" => "Meal"}})
    {:noreply, socket}
  end

  # Navigating hands the viewed date to the parent (which `push_patch`es to
  # `/calendar/ondate/:date` and reloads that week's meals, re-running update/2).
  defp go_to(socket, %Date{} = date) do
    send(self(), {:particular_date, %{"date" => Date.to_string(date)}})
    socket
  end

  ## ------------------------------------ Aggregation ---------------------------

  # `date => %{meals, total_nutrients, macro, meal_count, total_items, type_summaries}`
  # (macro/total_nutrients nil on empty days). Mirrors `MealCore.build_day_summaries`.
  defp build_day_summaries(user_meals, days, language) do
    Map.new(days, fn day ->
      meals = Enum.filter(user_meals, fn m -> NaiveDateTime.to_date(m.start_dt) == day end)
      {day, summarize(meals, language)}
    end)
  end

  defp summarize([], _language),
    do: %{meals: [], total_nutrients: nil, macro: nil, meal_count: 0, total_items: 0, type_summaries: []}

  defp summarize(meals, language) do
    total = Nu.summarize_meals_nutrients(meals)

    %{
      meals: meals,
      total_nutrients: total,
      macro: Nu.macro_summary(total),
      meal_count: length(meals),
      total_items: total_items(meals),
      type_summaries: meal_type_summaries(meals, language)
    }
  end

  defp meal_type_summaries(meals, language) do
    by_type = Enum.group_by(meals, fn m -> Map.get(m, :meal_type) end)

    for meal_type <- MealType.ordered() ++ [nil],
        group = by_type[meal_type],
        group not in [nil, []] do
      %{
        meal_type: meal_type,
        label: MehungryWeb.MealTypeLabels.label(meal_type, language),
        meals: group
      }
    end
  end

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
        total = meals |> Nu.summarize_meals_nutrients() |> scale_nutrients(days_in_week)

        %{
          meal_count: length(meals),
          total_items: total_items(meals),
          macro: Nu.macro_summary(total)
        }
    end
  end

  defp total_items(meals) do
    Enum.sum(
      Enum.map(meals, fn m ->
        length(m.recipe_user_meals) + length(m.ingredient_user_meals) +
          length(Map.get(m, :free_food_user_meals, []))
      end)
    )
  end

  # Scales every nutrient amount by 1/divisor (week total → daily average),
  # preserving the map shape the summary expects. (Same as MealCore.scale_nutrients.)
  defp scale_nutrients(total_nutrients, divisor) when divisor > 0 do
    Map.new(total_nutrients, fn
      {label, %{"amount" => amount} = nutrient} when is_number(amount) ->
        {label, Map.put(nutrient, "amount", amount / divisor)}

      {label, nutrient} ->
        {label, nutrient}
    end)
  end

  ## ------------------------------------ View helpers --------------------------

  defp meal_count(nil), do: 0
  defp meal_count(%{meal_count: n}), do: n

  defp empty_day?(nil), do: true
  defp empty_day?(%{meal_count: 0}), do: true
  defp empty_day?(_), do: false

  # Count of flagged (avoid-listed) items across the day.
  defp flagged_count(nil, _terms), do: 0
  defp flagged_count(_summary, []), do: 0

  defp flagged_count(summary, terms) do
    summary.meals
    |> Enum.flat_map(&item_titles/1)
    |> Enum.count(fn title -> MealPlanAgent.matched_avoid_terms([title], terms) != [] end)
  end

  defp item_titles(meal) do
    Enum.map(meal.recipe_user_meals, & &1.title) ++
      Enum.map(meal.ingredient_user_meals, & &1.title) ++
      Enum.map(Map.get(meal, :free_food_user_meals, []), & &1.title)
  end

  # Over the target (with a 5% grace band) reads paprika; at/under reads basil.
  defp kcal_text_class(actual, target) when is_number(actual) and is_number(target) do
    if actual > target * 1.05, do: "text-paprika", else: "text-basil"
  end

  defp kcal_text_class(_actual, _target), do: "text-basil"

  # Week-strip dot: muted when empty / no target, paprika when over, basil at/under.
  defp dot_class(nil, _target), do: "bg-ink-panel2"
  defp dot_class(%{meal_count: 0}, _target), do: "bg-ink-panel2"
  defp dot_class(%{macro: %{energy_kcal: kcal}}, target) when is_number(target) do
    if kcal > target * 1.05, do: "bg-paprika", else: "bg-basil"
  end

  defp dot_class(_summary, _target), do: "bg-basil"

  defp today_label(date) do
    if date == Date.utc_today(), do: gettext("Today"), else: gettext("Planned")
  end

  defp parse_date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> d
      _ -> Date.utc_today()
    end
  end

  # The goal/avoid coverage for one day, pulled from the week's `calendar_progress`
  # by that day's index (1..7 from `week_start`); falls back to week-level coverage
  # when a per-day breakdown is absent. (Mirrors `MealCore.day_progress`.)
  defp day_progress(progress, day) do
    day_index = Date.diff(day, progress.week_start) + 1

    case progress[:days_progress] && Map.get(progress.days_progress, day_index) do
      %{required: _, avoid: _} = dp -> dp
      _ -> %{required: progress.required, avoid: progress.avoid}
    end
  end

  defp beginning_of_week(%Date{} = d), do: Date.beginning_of_week(d)

  defp week_bounds(%Date{} = date) do
    first = Date.beginning_of_week(date)
    {first, Date.add(first, 6)}
  end

  defp day_name(%Date{} = date, lang), do: Locale.day_name(date, lang)
  defp day_name_short(%Date{} = date, lang), do: Locale.day_name(date, lang) |> String.slice(0, 3)
  defp month_short(%Date{} = date, lang), do: Locale.month_short(date, lang)
end
