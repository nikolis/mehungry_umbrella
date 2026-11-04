defmodule MehungryWeb.NutrientAnalysisComponent do
  @moduledoc """
  The per-day "full nutrition detail" modal reached from the `Reader`'s
  "Nutrition detail →" / "View full nutrition detail →" links
  (`/calendar/details/:date`).

  It loads the given day's meals through the same calendar pipeline the Reader
  uses (`History.list_calendar_user_meals/3` + `History.format_user_meals/2`) and
  aggregates them with `Mehungry.NutrientUtils.summarize_meals_nutrients/1`, so
  the numbers here can never drift from the Reader's status band. The aggregate is
  the same `name => node` tree a recipe carries, so we render it through the
  shared `MehungryWeb.NutritionAccordion` — identical to the recipe-details
  "Nutrition Facts" view: folding accordion rows, Calories/Carbs/Fat/Vitamins/
  Minerals ordering, `FattyAcidMatcher`-humanized fatty-acid labels, and locale
  translation.
  """
  use MehungryWeb, :live_component

  alias Mehungry.History
  alias Mehungry.NutrientUtils, as: Nu

  @impl true
  def update(assigns, socket) do
    date = to_date(assigns.particular_date)
    language = Map.get(assigns, :current_language, "en")

    nutrients =
      History.list_calendar_user_meals(assigns.current_user.id, date, date)
      |> History.format_user_meals(language)
      |> Nu.summarize_meals_nutrients()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(date: date, language: language, nutrients: nutrients)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h3 class="font-display font-medium text-parchment text-lg mb-1 flex items-center gap-2">
        <svg class="w-5 h-5 text-basil" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
          />
        </svg>
        {gettext("Nutrition detail")}
      </h3>
      <p class="text-parchment-dim/70 text-xs mb-3">
        {Calendar.strftime(@date, "%A, %d %b %Y")}
      </p>

      <div class="bg-ink-panel border border-ink-panel2 rounded-xl overflow-hidden">
        <MehungryWeb.NutritionAccordion.nutrition_accordion
          nutrients={@nutrients}
          show_title={false}
          locale={@language}
          max_height="600px"
          accordion_id={"nutrition-detail-#{Date.to_iso8601(@date)}"}
        />
      </div>
    </div>
    """
  end

  # The route param arrives as an ISO-8601 string; tolerate a %Date{} too.
  defp to_date(%Date{} = date), do: date
  defp to_date(date) when is_binary(date), do: Date.from_iso8601!(date)
end
