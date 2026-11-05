defmodule MehungryWeb.CalendarLive.Calendar.MealCore do
  @moduledoc """
  Shared, stateless calendar rendering — the meal card, the per-day/weekly
  nutrition summary card (+ its macro/micro pies), the nutrient badge row, and
  the private day-note field. Used by the consumer `Reader`, the nutritionist
  `Editor`, and the public `LandingLive` demo, so the exact same card + nutrition
  presentation renders everywhere while each surface owns its own layout/IA.
  (Extracted from the former `Calendar.Widget`.)
  """
  use MehungryWeb, :html

  alias MehungryWeb.SvgComponents
  alias Mehungry.NutrientUtils, as: Nu

  # Public entry (used by `LandingLive` with raw meals): filters + aggregates a
  # single day's meals and renders its summary card. Returns nil for an empty day.
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
  # (`%{meals: _, total_nutrients: _}`). Only reached from `get_chart/4` for a
  # populated day, so `total_nutrients` is always a map here.
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
      title: gettext("Daily Summary"),
      subtitle: nil,
      foldable: true,
      show_tags: day != current_date,
      # Day view defaults to the macro donut only; the micronutrient pie is
      # revealed on demand to cut visual noise.
      micro_hidden: true
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
    total_items =
      Enum.sum(
        Enum.map(meals, fn m ->
          length(m.recipe_user_meals) + length(m.ingredient_user_meals)
        end)
      )

    # Macro/energy numbers come from the shared `Nu.macro_summary/1` so the header
    # badges and the shareable weekly-plan card never disagree.
    Nu.macro_summary(total_nutrients)
    |> Map.merge(%{
      meal_count: length(meals),
      total_items: total_items,
      calorie_target: calorie_target
    })
  end

  defp to_number(n) when is_number(n), do: n * 1.0
  defp to_number(_), do: 0.0

  # Colour the actual kcal relative to the target: paprika when over, basil when
  # at/under. A 5% grace band keeps small overages from reading as "over".
  defp target_kcal_class(actual, target) when is_number(actual) and is_number(target) do
    if actual > target * 1.05, do: "text-paprika", else: "text-basil"
  end

  defp target_kcal_class(_actual, _target), do: "text-basil"

  # The nutrient badge row (meals · items, kcal, protein, carbs, fat) shared by
  # the summary-card headers and each day's accordion header.
  def summary_tags(assigns) do
    ~H"""
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@meal_count}</span>
      {ngettext("meal", "meals", @meal_count)} ·
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@total_items}</span>
      {ngettext("item", "items", @total_items)}
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
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@protein_g}</span>g {gettext("protein")}
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@fat_g}</span>g {gettext("fat")}
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@carbs_g}</span>g {gettext("carbs")}
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@sugars_g}</span>g {gettext("sugars")}
    </span>
    <span class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs">
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@fiber_g}</span>g {gettext("fiber")}
    </span>
    <%!-- Sodium + saturated fat matter for the conditions people track (BP, heart,
          kidney). They're hidden when 0 — many logged recipes simply lack the data,
          and a real-looking "0mg" would misrepresent "not recorded". --%>
    <span
      :if={@sodium_mg > 0}
      class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs"
    >
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@sodium_mg}</span>mg {gettext(
        "sodium"
      )}
    </span>
    <span
      :if={@saturated_fat_g > 0}
      class="px-2.5 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim text-xs"
    >
      <span class="text-basil font-bold [font-variant-numeric:tabular-nums]">{@saturated_fat_g}</span>g {gettext(
        "sat. fat"
      )}
    </span>
    """
  end

  def summary_card(assigns) do
    # Invoked by hand with a plain map (see render_day_chart/render_week_chart),
    # not a socket/assigns, so default the key with Map.put_new — assign_new/3
    # requires change-tracking metadata a plain map doesn't carry.
    assigns = Map.put_new(assigns, :micro_hidden, false)

    ~H"""
    <div class="mt-2 rounded-xl border border-ink-panel2 overflow-hidden bg-ink-panel">
      <button
        type="button"
        disabled={!@foldable}
        aria-expanded="false"
        aria-controls={"summary-body-" <> @id_key}
        class={[
          "w-full text-left flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3 bg-black/20 border-b border-ink-panel2",
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
            |> Phoenix.LiveView.JS.toggle_attribute({"aria-expanded", "true", "false"})
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
            sodium_mg={@sodium_mg}
            saturated_fat_g={@saturated_fat_g}
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
      </button>
      <div
        id={"summary-body-" <> @id_key}
        class={["flex flex-col sm:flex-row min-h-0", @foldable && "hidden"]}
      >
        <div
          class="flex-1 sm:border-r border-b sm:border-b-0 border-ink-panel2 overflow-y-auto"
          style="max-height: 400px;"
        >
          {MehungryWeb.RecipeComponents.recipe_nutrients(@recipe, assigns[:current_language] || "en")}
        </div>
        <div class="flex-1 flex flex-col sm:flex-row items-stretch justify-center gap-2 p-4 sm:p-6">
          <div class="flex-1 flex flex-col items-center justify-center">
            <span class="font-display font-medium text-parchment-dim text-xs uppercase tracking-wide mb-1">
              {gettext("Macros")}
            </span>
            <%= if @macro_data == [] do %>
              <p class="text-parchment-dim/70 text-xs italic my-auto">{gettext("No macro data")}</p>
            <% else %>
              <.live_component
                module={MehungryWeb.CalendarLive.Calendar.PieChart}
                id={"macro-chart-" <> @id_key}
                data={@macro_data}
                origin_id={"macro-chart-" <> @id_key}
                size="20rem"
              />
            <% end %>
            <button
              :if={@micro_hidden and @micro_data != []}
              type="button"
              class="mt-3 text-xs text-basil hover:underline"
              phx-click={
                Phoenix.LiveView.JS.toggle(to: "#micro-col-" <> @id_key)
                |> Phoenix.LiveView.JS.toggle(to: "#micro-show-" <> @id_key)
                |> Phoenix.LiveView.JS.toggle(to: "#micro-hide-" <> @id_key)
              }
            >
              <span id={"micro-show-" <> @id_key}>{gettext("Show micronutrients")}</span>
              <span id={"micro-hide-" <> @id_key} class="hidden">{gettext("Hide micronutrients")}</span>
            </button>
          </div>
          <%!-- Only render the micronutrient column when there is micro data —
                an empty second column strands the macro pie off-centre in half
                the width. With no micros the macro pie centres in the full area. --%>
          <div
            :if={@micro_data != []}
            id={"micro-col-" <> @id_key}
            class={["flex-1 flex flex-col items-center justify-center", @micro_hidden && "hidden"]}
          >
            <span class="font-display font-medium text-parchment-dim text-xs uppercase tracking-wide mb-1">
              {gettext("Micronutrients")}
            </span>
            <.live_component
              module={MehungryWeb.CalendarLive.Calendar.PieChart}
              id={"micro-chart-" <> @id_key}
              data={@micro_data}
              origin_id={"micro-chart-" <> @id_key}
              size="20rem"
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

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
            category: MehungryWeb.NutrientLabels.translate_name(@macro_slice_labels[bucket]),
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
      String.contains?(label, "Energy") or String.contains?(label, "Vitamins") or
        String.contains?(label, "Water")
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

  # A private, condition-agnostic journal line for one day (symptoms / how I
  # felt / energy). No `phx-target`, so the submit routes to the parent calendar
  # LiveView (`save_day_note`); a blank body clears the note. Pre-filled with the
  # existing note. Keyed `id` per day so LiveView patches the right textarea.
  attr :day, :any, required: true
  attr :body, :string, default: nil

  def day_note_form(assigns) do
    ~H"""
    <form
      id={"day-note-form-" <> Date.to_string(@day)}
      phx-submit="save_day_note"
      class="px-3 sm:px-4 pb-3 pt-1"
    >
      <input type="hidden" name="date" value={Calendar.strftime(@day, "%Y-%m-%d")} />
      <label class="block text-parchment-dim/70 text-[11px] uppercase tracking-wide mb-1">
        {gettext("Day note")}
        <span class="normal-case tracking-normal text-parchment-dim/50">
          · {gettext("private — how you felt today")}
        </span>
      </label>
      <div class="flex items-start gap-2">
        <textarea
          id={"day-note-" <> Date.to_string(@day)}
          name="body"
          rows="1"
          placeholder={gettext("e.g. felt bloated after lunch, good energy…")}
          class="flex-1 bg-ink border border-ink-panel2 rounded-lg px-3 py-2 text-parchment text-xs resize-y focus:outline-none focus:border-paprika min-h-[2.25rem]"
        >{@body}</textarea>
        <button
          type="submit"
          class="shrink-0 px-3 py-2 rounded-lg border border-ink-panel2 text-parchment-dim hover:text-parchment hover:border-parchment-dim text-xs font-medium transition"
          phx-disable-with="…"
        >
          {gettext("Save")}
        </button>
      </div>
    </form>
    """
  end

  def card_meal(assigns) do
    # `recipe_id` is the numeric recipe id for recipe cards (nil for ingredient
    # cards); it gates the "View recipe" button that opens the details modal.
    assigns = assign_new(assigns, :recipe_id, fn -> nil end)

    # Species-derived emoji for ingredient cards (nil for recipe/landing cards,
    # which don't pass it) — rendered inline before the title.
    assigns = assign_new(assigns, :icon, fn -> nil end)

    # `ingredient_user_meal_id` is the logged ingredient entry's row id (nil for
    # recipe/landing cards); it gates the "View ingredient" button that opens the
    # ingredient details modal — the ingredient-side mirror of "View recipe".
    assigns = assign_new(assigns, :ingredient_user_meal_id, fn -> nil end)

    # The user's personal avoid terms this food's title matches (reusing the
    # meal-plan enforcement engine's substring match). Empty list = not flagged;
    # defaulted so landing/demo cards that don't pass the assign render clean.
    assigns =
      assign_new(assigns, :avoided, fn ->
        Mehungry.AI.Agents.MealPlanAgent.matched_avoid_terms(
          [assigns.title],
          Map.get(assigns, :avoid_terms, [])
        )
      end)

    ~H"""
    <div class={[
      "bg-black/20 border rounded-xl p-3 sm:p-4 hover:bg-black/30 transition-colors",
      if(@avoided == [], do: "border-ink-panel2", else: "border-amber-500/50")
    ]}>
      <div class="flex gap-4 items-center">
        <div class="relative flex-shrink-0 h-20 w-20 sm:h-24 sm:w-24 rounded-xl overflow-hidden">
          <%= cond do %>
            <% not is_nil(@img_url) -> %>
              <img src={@img_url} class="h-full w-full object-cover" />
            <% not is_nil(@icon) -> %>
              <div class="h-full w-full bg-ink-panel2 flex items-center justify-center text-4xl sm:text-5xl" aria-hidden="true">
                {@icon}
              </div>
            <% true -> %>
              <div class="h-full w-full bg-ink-panel2 flex items-center justify-center">
                {SvgComponents.get_default_recipe_image(assigns)}
              </div>
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
            <button
              class="absolute right-1 top-9 bg-ink/80 hover:bg-ink-panel2 text-parchment p-1 rounded-full transition-colors"
              type="button"
              title={gettext("Log this again today")}
              aria-label={gettext("Log this again today")}
              phx-click="copy_meal_to_today"
              phx-value-id={@actual_meal.id}
              data-confirm={gettext("Copy this meal to today?")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                class="size-3.5"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m11.25 5.5H16.5a1.125 1.125 0 0 1-1.125-1.125v-3.5"
                />
              </svg>
            </button>
          <% end %>
        </div>
        <div class="flex-1 min-w-0">
          <h3 class={"font-display font-medium text-base leading-snug mb-1 " <> @card_meal_text}>
            {@title}
          </h3>
          <div
            :if={@avoided != []}
            class="inline-flex items-center gap-1 mb-2 px-2 py-0.5 rounded-full bg-amber-500/15 text-amber-300 text-[0.7rem] font-semibold"
            title={gettext("On your avoid list: %{terms}", terms: Enum.join(@avoided, ", "))}
          >
            <svg class="w-3 h-3 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 9v2m0 4h.01M4.93 4.93l14.14 14.14M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
              />
            </svg>
            {gettext("On your avoid list")}
          </div>
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
          <%= if @ingredient_user_meal_id do %>
            <button
              type="button"
              phx-click="show_ingredient_details"
              phx-value-id={@ingredient_user_meal_id}
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
              {gettext("View ingredient")}
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

end
