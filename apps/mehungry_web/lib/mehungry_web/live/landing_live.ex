defmodule MehungryWeb.LandingLive do
  use MehungryWeb, :live_view
  use MehungryWeb.Presence, :user_tracking

  import MehungryWeb.SvgComponents
  import Ecto.Query

  @impl true
  def handle_event("resize_chart", %{"width" => width}, socket) do
    for _child_id <- socket.assigns.child_ids do
      send_update(MehungryWeb.CalendarLive.Calendar.PieChart, resize: width)
    end

    {:noreply, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    # For the meal planning demo, prefer the AI bot user's recipe, then fall back
    # to any recipe in the DB — we only need nutrients for the chart, not an image.
    now = Date.utc_today()
    recipes = find_bot_recipe(now.month, now.year) || []
    recipe = List.first(recipes)

    {:ok,
     assign(socket,
       page_title: gettext("M3Hungry — Know What's On Your Plate"),
       page_description:
         gettext(
           "Track 168 nutrients per meal. Generate AI recipes backed by USDA FoodData Central. Plan your week. Share what you cook."
         ),
       recipe: recipe,
       recipes: recipes,
       child_ids: []
     )}
  end

  # Picks up to 3 recipes for the meal-planning demo. Prefers the current month's
  # AI bot user, then falls back to any public recipe — but only ones that carry
  # nutrients, since the chart needs them. Always returns a list.
  defp find_bot_recipe(month, year) do
    bot_recipes =
      case Mehungry.AI.Bot.get_active_config_for_month(month, year) do
        %{bot_user_id: bot_user_id} ->
          Mehungry.Repo.all(recipes_with_nutrients_query(user_id: bot_user_id))

        _ ->
          []
      end

    case bot_recipes do
      [] -> Mehungry.Repo.all(recipes_with_nutrients_query([]))
      recipes -> recipes
    end
  end

  # Public recipes that have a non-empty `nutrients` map, 3 at random. Optionally
  # scoped to a single author via the `:user_id` option.
  defp recipes_with_nutrients_query(opts) do
    query =
      from(r in Mehungry.Food.Recipe,
        where:
          (is_nil(r.private) or not r.private) and fragment("? <> '{}'::jsonb", r.nutrients),
        order_by: fragment("RANDOM()"),
        limit: 3
      )

    case Keyword.fetch(opts, :user_id) do
      {:ok, user_id} -> from(r in query, where: r.user_id == ^user_id)
      :error -> query
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="landing-page bg-ink text-parchment">
      <%!-- ═══════════════════════════════════════════ NAV ══════════════════════════════════════════════ --%>
      <nav
        class="fixed inset-x-0 top-0 z-50 h-24 border-b border-ink-panel2 bg-ink/90 backdrop-blur-md"
        aria-label="Main navigation"
      >
        <div class="mx-auto flex h-full max-w-6xl items-center justify-between px-4 sm:px-6">
          <span
            class="contents"
            style="--logo-text-color: #F4EEDD; --logo-tagline-color: #A9A08C;"
          >
            <.get_logo id="landing-nav" class="h-16 w-[304px]" show_tagline />
          </span>

          <div class="hidden items-center gap-8 text-sm md:flex">
            <a href="#features" class="text-parchment-dim transition-colors hover:text-parchment">
              {gettext("Features")}
            </a>
            <a href="#pricing" class="text-parchment-dim transition-colors hover:text-parchment">
              {gettext("Pricing")}
            </a>
            <a
              href={"/#{@current_language}/browse"}
              class="text-parchment-dim transition-colors hover:text-parchment"
            >
              {gettext("Browse Recipes")}
            </a>
          </div>

          <div class="flex items-center gap-3">
            <a
              href="/login"
              class="hidden text-sm text-parchment-dim transition-colors hover:text-parchment sm:block"
            >
              {gettext("Sign in")}
            </a>
            <a
              href="/register"
              class="rounded-md border border-paprika/40 px-4 py-2 text-sm font-semibold text-paprika-soft transition-colors hover:border-paprika hover:text-parchment focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-paprika"
            >
              {gettext("Get started")}
            </a>
          </div>
        </div>
      </nav>

      <%!-- ═══════════════════════════════════════════ HERO ══════════════════════════════════════════════ --%>
      <section class="relative bg-ink pb-20 pt-32 sm:pt-40" aria-labelledby="hero-heading">
        <%!-- Accent line at top --%>
        <div class="pointer-events-none absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-paprika/30 to-transparent">
        </div>

        <div class="relative mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mx-auto max-w-3xl text-center">
            <%!-- Eyebrow --%>
            <div class="mb-6 inline-flex items-center gap-2 rounded-full border border-basil/20 bg-basil/10 px-3 py-1 text-xs font-medium text-basil">
              <span class="h-1.5 w-1.5 rounded-full bg-basil" aria-hidden="true"></span>
              {gettext("Backed by USDA FoodData Central")}
            </div>

            <%!-- Headline --%>
            <h1
              id="hero-heading"
              class="mb-5 font-display text-5xl font-medium leading-[1.1] tracking-tight text-parchment sm:text-6xl md:text-7xl"
            >
              {gettext("Know what's on your plate.")}
              <em class="not-italic text-paprika-soft">{gettext("Really.")}</em>
            </h1>

            <p class="mb-9 text-lg leading-relaxed text-parchment-dim sm:text-xl">
              {gettext(
                "Track 168 nutrients per meal. Generate AI recipes backed by USDA science. Plan your week. Share what you cook."
              )}
            </p>

            <div class="flex flex-col items-center justify-center gap-3 sm:flex-row">
              <a
                href="/register"
                class="w-full rounded-lg bg-paprika px-8 py-3 text-base font-bold text-ink shadow-lg shadow-black/30 transition-all hover:bg-paprika-soft sm:w-auto"
              >
                {gettext("Start for free")}
              </a>
              <a
                href={"/#{@current_language}/browse"}
                class="w-full rounded-lg border border-ink-panel2 px-8 py-3 text-base font-medium text-parchment-dim transition-all hover:border-parchment-dim hover:text-parchment sm:w-auto"
              >
                {gettext("Browse recipes →")}
              </a>
            </div>

            <%!-- Trust strip — only honest, verifiable claims --%>
            <div
              class="mt-12 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-parchment-dim"
              aria-label="Key facts"
            >
              <span class="flex items-center gap-1.5">
                <svg
                  class="h-4 w-4 text-basil-soft"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">10,000+</span>
                {gettext("foods in the database")}
              </span>
              <span class="flex items-center gap-1.5">
                <svg
                  class="h-4 w-4 text-basil-soft"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">168</span>
                {gettext("nutrients tracked per food")}
              </span>
              <span class="flex items-center gap-1.5">
                <svg
                  class="h-4 w-4 text-basil-soft"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                {gettext("Free to start · No credit card")}
              </span>
            </div>
          </div>

          <%!-- Hero visual: real recipe widget from DB --%>
          <%= if @recipe do %>
            <div class="relative mx-auto mt-16 max-w-2xl">
              <div class="overflow-hidden rounded-2xl border border-ink-panel2 bg-ink-panel/80 shadow-2xl shadow-black/40">
                <%!-- Browser chrome --%>
                <div class="flex items-center gap-1.5 border-b border-ink-panel2 bg-ink-panel px-4 py-3">
                  <span class="h-2.5 w-2.5 rounded-full bg-red-500/60" aria-hidden="true"></span>
                  <span class="h-2.5 w-2.5 rounded-full bg-yellow-500/60" aria-hidden="true"></span>
                  <span class="h-2.5 w-2.5 rounded-full bg-green-500/60" aria-hidden="true"></span>
                  <span class="ml-3 text-xs text-parchment-dim">m3hungry.com/calendar</span>
                </div>
                <div class="p-4">
                  <MehungryWeb.CalendarLive.Calendar.Widget.card_meal
                    img_url={@recipe.image_url}
                    card_meal_text="text-parchment"
                    recipe={@recipe}
                    cooking_portions="1"
                    consume_portions="1"
                    actual_meal={
                      %{
                        cooking_portions: 1,
                        consume_portions: 1,
                        recipe: @recipe,
                        id: "hero_meal"
                      }
                    }
                    title={gettext("Lunch")}
                    myself="hero"
                    id="hero_meal"
                  />
                </div>
              </div>

              <%!-- Floating badge --%>
              <div class="absolute -right-2 -top-3 hidden rounded-xl border border-basil/30 bg-ink-panel px-3 py-2 shadow-lg sm:block">
                <p class="text-xs font-bold text-basil [font-variant-numeric:tabular-nums]">
                  {gettext("168 nutrients")}
                </p>
                <p class="text-xs text-parchment-dim">{gettext("per serving, from USDA")}</p>
              </div>
            </div>
          <% end %>
        </div>
      </section>

      <%!-- ══════════════════════ THE DEPTH COMPARISON — signature section ══════════════════════════════ --%>
      <section
        id="features"
        class="border-y border-ink-panel2 bg-ink py-24"
        aria-labelledby="depth-heading"
        style="scroll-margin-top: 4rem;"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-14 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-basil">
              {gettext("Nutrition depth")}
            </p>
            <h2
              id="depth-heading"
              class="font-display text-4xl font-medium text-parchment sm:text-5xl"
            >
              {gettext("Not 4 nutrients.")}
              <span class="text-basil [font-variant-numeric:tabular-nums]">168.</span>
            </h2>
            <p class="mx-auto mt-4 max-w-xl text-parchment-dim">
              {gettext(
                "Most trackers give you calories and macros. We give you the full picture — the same data nutritionists and researchers actually use."
              )}
            </p>
          </div>

          <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
            <%!-- Other apps --%>
            <div class="rounded-2xl border border-ink-panel2 bg-black/20 p-6">
              <p class="mb-4 text-sm font-medium text-parchment-dim">
                {gettext("What most apps track")}
              </p>
              <div class="space-y-2">
                <%= for {nutrient, unit} <- [
                {"Calories", "kcal"},
                {"Protein", "g"},
                {"Carbohydrates", "g"},
                {"Total Fat", "g"}
              ] do %>
                  <div class="flex items-center justify-between rounded-lg bg-ink-panel2/50 px-4 py-2.5">
                    <span class="text-sm text-parchment-dim">{nutrient}</span>
                    <span class="text-xs text-parchment-dim/60">{unit}</span>
                  </div>
                <% end %>
                <div class="flex items-center justify-center py-4">
                  <span class="text-sm text-parchment-dim/50">{gettext("… and that's it")}</span>
                </div>
              </div>
            </div>

            <%!-- M3Hungry — real USDA nutrient names --%>
            <div class="rounded-2xl border border-basil/20 bg-ink-panel p-6 ring-1 ring-basil/10">
              <p class="mb-4 text-sm font-medium text-basil">{gettext("What M3Hungry tracks")}</p>
              <div class="space-y-1.5">
                <%= for {nutrient, unit, highlight} <- [
                {"Energy", "kcal", false},
                {"Protein", "g", false},
                {"Total Fat", "g", false},
                {"Carbohydrates", "g", false},
                {"Dietary Fiber", "g", true},
                {"Saturated Fat (SFA)", "g", true},
                {"Monounsaturated Fat (MUFA)", "g", true},
                {"PUFA 18:2 n-6 (Linoleic acid)", "g", true},
                {"DHA 22:6 n-3", "g", true},
                {"Vitamin K (phylloquinone)", "µg", true},
                {"Folate, food", "µg DFE", true},
                {"Selenium", "µg", true}
              ] do %>
                  <div class={[
                    "flex items-center justify-between rounded-lg px-3 py-2",
                    if(highlight,
                      do: "border border-basil/15 bg-basil/10",
                      else: "bg-black/20"
                    )
                  ]}>
                    <span class={[
                      "text-sm",
                      if(highlight, do: "text-parchment", else: "text-parchment-dim")
                    ]}>
                      {nutrient}
                    </span>
                    <span class={[
                      "text-xs",
                      if(highlight, do: "text-basil", else: "text-parchment-dim/60")
                    ]}>
                      {unit}
                    </span>
                  </div>
                <% end %>

                <div class="flex items-center justify-center rounded-lg border border-dashed border-basil/20 py-2.5">
                  <span class="text-sm font-medium text-basil">
                    + <span class="font-bold [font-variant-numeric:tabular-nums]">156</span>
                    {gettext("more nutrients tracked")}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════════ MEAL PLANNING ══════════════════════════════════════════════════ --%>
      <section class="bg-ink-panel py-24" aria-labelledby="meal-planning-heading">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="grid grid-cols-1 items-center gap-12 md:grid-cols-2">
            <div>
              <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
                {gettext("Meal planning")}
              </p>
              <h2
                id="meal-planning-heading"
                class="mb-4 font-display text-4xl font-medium text-parchment"
              >
                {gettext("Your week, planned. Your nutrition, balanced.")}
              </h2>
              <p class="mb-6 text-parchment-dim">
                {gettext(
                  "Add any recipe to your meal calendar. See your daily nutrition at a glance across every tracked nutrient. Generate your shopping list automatically from your weekly plan."
                )}
              </p>
              <ul class="space-y-3 text-sm text-parchment">
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Calendar view for breakfast, lunch, dinner, and snacks")}
                </li>
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Daily nutrition totals across all")}
                  <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">168</span>
                  {gettext("tracked nutrients")}
                </li>
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Import meal ingredients into your shopping basket with one tap")}
                </li>
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Adjust portion sizes and serving counts per meal")}
                </li>
              </ul>
              <a
                href="/register"
                class="mt-8 inline-flex items-center gap-1 text-sm font-semibold text-paprika-soft transition-colors hover:text-paprika"
              >
                {gettext("Plan your week →")}
              </a>
            </div>

            <%!-- Meal planning demo: recipe card + nutrition chart from the AI bot user --%>
            <div
              class="overflow-hidden rounded-2xl border border-ink-panel2 bg-ink p-4"
              aria-label="Meal planning preview"
            >
              <%= if @recipe do %>
                <MehungryWeb.CalendarLive.Calendar.Widget.card_meal
                  img_url={@recipe.image_url}
                  card_meal_text="text-parchment"
                  recipe={@recipe}
                  cooking_portions="1"
                  consume_portions="1"
                  actual_meal={
                    %{
                      cooking_portions: 1,
                      consume_portions: 1,
                      recipe: @recipe,
                      id: "plan_meal"
                    }
                  }
                  title={gettext("Lunch")}
                  myself="plan"
                  id="plan_meal"
                />
                {MehungryWeb.CalendarLive.Calendar.Widget.get_chart(
                  [
                    %{
                      start_dt: NaiveDateTime.local_now(),
                      ingredient_user_meals: [],
                      recipe_user_meals: [
                        %{
                          recipe_nutrients: @recipe.nutrients,
                          cooking_portions: 1,
                          consume_portions: 1,
                          recipe: @recipe,
                          id: "plan_chart",
                          start_dt: NaiveDateTime.local_now()
                        }
                      ]
                    }
                  ],
                  Date.utc_today(),
                  "text-parchment"
                )}
              <% else %>
                <p class="text-sm text-parchment-dim">
                  {gettext("Add meals to your calendar to see your daily nutrition overview")}
                </p>
              <% end %>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════ RECIPE DISCOVERY + SOCIAL ══════════════════════════════════════════ --%>
      <section class="bg-ink py-24" aria-labelledby="discover-heading">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-12 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
              {gettext("Discover & share")}
            </p>
            <h2 id="discover-heading" class="font-display text-4xl font-medium text-parchment">
              {gettext("Recipes with the nutrition already done.")}
            </h2>
            <p class="mx-auto mt-4 max-w-xl text-parchment-dim">
              {gettext(
                "Browse community recipes — each one built with real USDA ingredients, so the nutrition facts are exact, not estimated. Save any recipe to your calendar in one click."
              )}
            </p>
          </div>

          <%!-- Real recipe cards from DB --%>
          <%= if length(@recipes) > 0 do %>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <%= for recipe <- Enum.take(@recipes, 3) do %>
                <a
                  href={"/#{@current_language}/browse/#{recipe.id}"}
                  class="group overflow-hidden rounded-xl border border-ink-panel2 bg-ink-panel transition-all hover:border-basil/30 hover:shadow-lg hover:shadow-black/20 focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika"
                >
                  <%= if recipe.image_url do %>
                    <div class="aspect-video overflow-hidden">
                      <img
                        src={recipe.image_url}
                        alt={recipe.title}
                        class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
                        loading="lazy"
                      />
                    </div>
                  <% else %>
                    <div class="flex aspect-video items-center justify-center bg-ink-panel2">
                      <svg
                        class="h-8 w-8 text-parchment-dim"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                        aria-hidden="true"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          stroke-width="1.5"
                          d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                        />
                      </svg>
                    </div>
                  <% end %>
                  <div class="p-4">
                    <h3 class="line-clamp-1 font-display font-medium text-parchment">
                      {recipe.title}
                    </h3>
                    <p class="mt-1 text-xs text-parchment-dim">
                      <%= if recipe.servings do %>
                        {recipe.servings} {gettext("servings")}<%= if recipe.cooking_time_lower_limit do %>
                          &nbsp;· {recipe.cooking_time_lower_limit} {gettext("min")}
                        <% end %>
                      <% end %>
                    </p>
                    <div class="mt-2.5">
                      <span class="inline-block rounded-full border border-basil/20 bg-basil/10 px-2.5 py-0.5 text-xs text-basil">
                        {gettext("168 nutrients tracked")}
                      </span>
                    </div>
                  </div>
                </a>
              <% end %>
            </div>
          <% end %>

          <div class="mt-8 text-center">
            <a
              href={"/#{@current_language}/browse"}
              class="rounded-lg border border-ink-panel2 px-6 py-2.5 text-sm font-medium text-parchment-dim transition-all hover:border-parchment-dim hover:text-parchment"
            >
              {gettext("Browse all recipes →")}
            </a>
          </div>

          <%!-- Social proof — real features, not fake stats --%>
          <div class="mt-14 grid grid-cols-1 gap-4 border-t border-ink-panel2 pt-10 sm:grid-cols-3">
            <div class="text-center">
              <p class="text-sm font-medium text-parchment">{gettext("Post your recipes")}</p>
              <p class="mt-1 text-sm text-parchment-dim">
                {gettext("Share what you cook and tag it with food hashtags for others to discover")}
              </p>
            </div>
            <div class="text-center">
              <p class="text-sm font-medium text-parchment">{gettext("Comment & vote")}</p>
              <p class="mt-1 text-sm text-parchment-dim">
                {gettext("Leave feedback, ask questions, and vote on the recipes you love")}
              </p>
            </div>
            <div class="text-center">
              <p class="text-sm font-medium text-parchment">{gettext("Follow creators")}</p>
              <p class="mt-1 text-sm text-parchment-dim">
                {gettext("Build a feed from the cooks whose nutrition philosophy matches yours")}
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════════════ AI ASSISTANT ═══════════════════════════════════════════════ --%>
      <section
        class="border-y border-ink-panel2 bg-ink-panel/50 py-24"
        aria-labelledby="ai-heading"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="grid grid-cols-1 items-center gap-12 md:grid-cols-2">
            <%!-- Interface demo — labeled as example to avoid misleading --%>
            <div class="order-2 md:order-1" aria-label="AI recipe assistant interface example">
              <div class="overflow-hidden rounded-2xl border border-ink-panel2 bg-ink p-5">
                <div class="mb-4 flex items-center gap-2">
                  <span
                    class="h-2 w-2 rounded-full bg-paprika animate-pulse"
                    aria-hidden="true"
                  ></span>
                  <span class="text-xs text-parchment-dim">{gettext("AI Recipe Assistant")}</span>
                </div>

                <div class="mb-3 flex justify-end">
                  <div class="max-w-xs rounded-2xl rounded-tr-sm border border-paprika/20 bg-paprika/10 px-4 py-2.5 text-sm text-parchment">
                    {gettext("High-protein pasta under 600 kcal. Make it Mediterranean.")}
                  </div>
                </div>

                <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-4">
                  <p class="mb-1 text-sm font-semibold text-parchment">
                    {gettext("Mediterranean Chicken Orzo")}
                  </p>
                  <p class="mb-3 text-xs text-parchment-dim">
                    {gettext("Generated using USDA-verified ingredients")}
                  </p>
                  <div class="rounded-lg border border-basil/20 bg-basil/10 px-3 py-2.5">
                    <p class="text-xs font-medium text-basil-soft">
                      {gettext("Full 168-nutrient breakdown calculated from USDA data")}
                    </p>
                    <p class="mt-0.5 text-xs text-parchment-dim">
                      {gettext("Protein · Fatty acids · Vitamins · Minerals · Amino acids…")}
                    </p>
                  </div>
                  <p class="mt-2 text-right text-xs text-basil">
                    {gettext("View full breakdown →")}
                  </p>
                </div>

                <p class="mt-3 text-center text-xs text-parchment-dim/60">
                  {gettext("Example output — your results will vary by request")}
                </p>
              </div>
            </div>

            <div class="order-1 md:order-2">
              <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
                {gettext("AI-powered")}
              </p>
              <h2 id="ai-heading" class="mb-4 font-display text-4xl font-medium text-parchment">
                {gettext("Tell it what you want to eat. It handles the rest.")}
              </h2>
              <p class="mb-6 text-parchment-dim">
                {gettext(
                  "Describe your meal — a dietary goal, a cuisine, what's in your fridge. The AI generates a complete recipe with ingredients mapped directly to the USDA database, so you get exact nutrition data, not estimates."
                )}
              </p>
              <ul class="space-y-3 text-sm text-parchment">
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Recipes generated to your calorie and macro targets")}
                </li>
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Every ingredient mapped to USDA FoodData Central")}
                </li>
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Generate a full weekly meal plan in one request")}
                </li>
                <li class="flex items-start gap-2.5">
                  <svg
                    class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  {gettext("Save generated recipes directly to your calendar")}
                </li>
              </ul>
              <div class="mt-8 flex flex-col gap-2 sm:flex-row sm:items-center">
                <a
                  href="/register"
                  class="inline-flex items-center gap-1 text-sm font-semibold text-paprika-soft transition-colors hover:text-paprika"
                >
                  {gettext("Try the AI assistant →")}
                </a>
                <p class="text-xs text-parchment-dim">
                  {gettext("Mehungry Plus plan required · From €9.99/mo")}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- ═════════════════════ NUTRITION INTELLIGENCE (sustainability angle) ══════════════════════════ --%>
      <section class="bg-ink py-24" aria-labelledby="intelligence-heading">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-12 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-basil">
              {gettext("Nutrition intelligence")}
            </p>
            <h2 id="intelligence-heading" class="font-display text-4xl font-medium text-parchment">
              {gettext("Built for how nutrition actually works.")}
            </h2>
            <p class="mx-auto mt-4 max-w-xl text-parchment-dim">
              {gettext(
                "Nutrients don't exist in isolation. M3Hungry tracks how nutrients interact with each other — and adapts to the foods your body actually needs."
              )}
            </p>
          </div>

          <div class="grid grid-cols-1 gap-5 sm:grid-cols-3">
            <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-6">
              <div class="mb-4 flex h-10 w-10 items-center justify-center rounded-lg border border-basil/20 bg-basil/10">
                <svg
                  class="h-5 w-5 text-basil"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M13 10V3L4 14h7v7l9-11h-7z"
                  />
                </svg>
              </div>
              <h3 class="mb-2 font-display font-medium text-parchment">
                {gettext("Nutrient interactions")}
              </h3>
              <p class="text-sm text-parchment-dim">
                {gettext(
                  "Some nutrients enhance absorption; others inhibit it. Vitamin C improves iron uptake. Vitamin D activates calcium metabolism. We surface these relationships per recipe."
                )}
              </p>
            </div>

            <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-6">
              <div class="mb-4 flex h-10 w-10 items-center justify-center rounded-lg border border-ink-panel2 bg-black/20">
                <svg
                  class="h-5 w-5 text-parchment-dim"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 6V4m0 2a2 2 0 100 4m0-4a2 2 0 110 4m-6 4a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4m6 6v10m6-2a2 2 0 100-4m0 4a2 2 0 110-4m0 4v2m0-6V4"
                  />
                </svg>
              </div>
              <h3 class="mb-2 font-display font-medium text-parchment">
                {gettext("Dietary preferences")}
              </h3>
              <p class="text-sm text-parchment-dim">
                {gettext(
                  "Set dietary restrictions — vegetarian, gluten-free, specific allergies. Exclude ingredients or entire food categories from your experience. Your feed and AI adapt accordingly."
                )}
              </p>
            </div>

            <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-6">
              <div class="mb-4 flex h-10 w-10 items-center justify-center rounded-lg border border-basil/20 bg-basil/10">
                <svg
                  class="h-5 w-5 text-basil"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4"
                  />
                </svg>
              </div>
              <h3 class="mb-2 font-display font-medium text-parchment">
                {gettext("Survey-guided setup")}
              </h3>
              <p class="text-sm text-parchment-dim">
                {gettext(
                  "Complete a short dietary preferences survey when you join. Your food feed, recipe recommendations, and AI outputs adapt to your actual lifestyle and goals from the start."
                )}
              </p>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════════ FOR NUTRITIONISTS ══════════════════════════════════════════════ --%>
      <section
        class="border-y border-ink-panel2 bg-gradient-to-b from-ink-panel to-ink py-24"
        aria-labelledby="nutritionist-heading"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="overflow-hidden rounded-2xl border border-basil/20 bg-ink">
            <div class="grid grid-cols-1 md:grid-cols-2">
              <div class="p-8 sm:p-10">
                <div class="mb-4 inline-flex items-center gap-2 rounded-full border border-basil/20 bg-basil/10 px-3 py-1 text-xs font-medium text-basil">
                  {gettext("Professional tier")}
                </div>
                <h2
                  id="nutritionist-heading"
                  class="mb-4 font-display text-3xl font-medium text-parchment"
                >
                  {gettext("Built for nutritionists, not just individuals.")}
                </h2>
                <p class="mb-6 text-parchment-dim">
                  {gettext(
                    "Manage your client roster, assign meal plans, track progress, and schedule appointments — within the same platform your clients use to log their food."
                  )}
                </p>
                <ul class="space-y-2.5 text-sm text-parchment">
                  <li class="flex items-start gap-2">
                    <svg
                      class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    {gettext("Client invitation and management system")}
                  </li>
                  <li class="flex items-start gap-2">
                    <svg
                      class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    {gettext("View and manage client meal calendars")}
                  </li>
                  <li class="flex items-start gap-2">
                    <svg
                      class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    {gettext("Appointment scheduling with calendar view")}
                  </li>
                  <li class="flex items-start gap-2">
                    <svg
                      class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">30</span>
                    {gettext("AI recipe generations +")}
                    <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">10</span>
                    {gettext("meal plans per month")}
                  </li>
                </ul>
                <a
                  href="/register"
                  class="mt-8 inline-flex items-center gap-1 rounded-lg border border-basil/40 px-6 py-2.5 text-sm font-semibold text-basil transition-colors hover:border-basil hover:text-basil-soft"
                >
                  {gettext("Explore the professional tier →")}
                </a>
              </div>

              <%!-- Dashboard preview --%>
              <div class="hidden items-center justify-center border-l border-ink-panel2 bg-ink-panel/30 p-8 md:flex">
                <div class="w-full space-y-3" aria-hidden="true">
                  <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-4">
                    <p class="mb-2 text-xs text-parchment-dim">{gettext("Your clients")}</p>
                    <div class="flex items-center justify-between">
                      <span class="text-2xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                        —
                      </span>
                      <span class="text-xs text-basil">{gettext("Manage →")}</span>
                    </div>
                  </div>
                  <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-4">
                    <p class="mb-2 text-xs text-parchment-dim">{gettext("Upcoming appointments")}</p>
                    <div class="flex items-center justify-between">
                      <span class="text-2xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                        —
                      </span>
                      <span class="text-xs text-basil">{gettext("Calendar →")}</span>
                    </div>
                  </div>
                  <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-4">
                    <p class="mb-2 text-xs text-parchment-dim">{gettext("AI meal plans this month")}</p>
                    <div class="flex items-center gap-2">
                      <div class="h-2 flex-1 overflow-hidden rounded-full bg-ink-panel2">
                        <div class="h-full w-1/4 rounded-full bg-basil"></div>
                      </div>
                      <span class="text-xs text-parchment-dim [font-variant-numeric:tabular-nums]">
                        {gettext("0 / 10 used")}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════════════ PRICING ════════════════════════════════════════════════════ --%>
      <section
        id="pricing"
        class="bg-ink py-24"
        aria-labelledby="pricing-heading"
        style="scroll-margin-top: 4rem;"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-12 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
              {gettext("Pricing")}
            </p>
            <h2 id="pricing-heading" class="font-display text-4xl font-medium text-parchment">
              {gettext("Start free. Upgrade when you're ready.")}
            </h2>
            <p class="mt-3 text-parchment-dim">
              {gettext("All plans include full nutrition tracking. AI features are the upgrade.")}
            </p>
          </div>

          <div class="grid grid-cols-1 gap-6 md:grid-cols-3">
            <%!-- Free --%>
            <div class="rounded-2xl border border-ink-panel2 bg-ink-panel p-6">
              <h3 class="mb-1 text-base font-semibold text-parchment">{gettext("Free")}</h3>
              <div class="mb-1 flex items-baseline gap-1">
                <span class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                  €0
                </span>
                <span class="text-sm text-parchment-dim">{gettext("/month")}</span>
              </div>
              <p class="mb-5 text-xs text-parchment-dim">{gettext("No credit card required")}</p>
              <ul class="mb-6 space-y-2.5 text-sm">
                <%= for text <- [
                gettext("Full nutrition tracking (168 nutrients)"),
                gettext("Unlimited manual recipe creation"),
                gettext("Meal calendar planning"),
                gettext("Browse and share community recipes"),
                gettext("Shopping basket")
              ] do %>
                  <li class="flex items-center gap-2 text-parchment">
                    <svg
                      class="h-3.5 w-3.5 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2.5"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    {text}
                  </li>
                <% end %>
                <li class="flex items-center gap-2 text-parchment-dim/60">
                  <svg
                    class="h-3.5 w-3.5 shrink-0 text-parchment-dim/60"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2.5"
                      d="M6 18L18 6M6 6l12 12"
                    />
                  </svg>
                  <span class="line-through">{gettext("AI recipe generator")}</span>
                </li>
              </ul>
              <a
                href="/register"
                class="block w-full rounded-lg border border-ink-panel2 py-2 text-center text-sm font-medium text-parchment-dim transition-colors hover:border-parchment-dim hover:text-parchment focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika"
              >
                {gettext("Get started free")}
              </a>
            </div>

            <%!-- Plus — most popular --%>
            <div class="relative rounded-2xl border-2 border-paprika bg-ink-panel p-6 shadow-xl shadow-black/20">
              <div class="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-paprika px-3 py-0.5 text-xs font-bold text-ink">
                {gettext("Most popular")}
              </div>
              <h3 class="mb-1 text-base font-semibold text-parchment">Mehungry Plus</h3>
              <div class="mb-1 flex items-baseline gap-1">
                <span class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                  €9.99
                </span>
                <span class="text-sm text-parchment-dim">{gettext("/month")}</span>
              </div>
              <p class="mb-5 text-xs text-parchment-dim">
                {gettext("or €99/yr —")} <span class="text-basil-soft">{gettext("save 17%")}</span>
              </p>
              <ul class="mb-6 space-y-2.5 text-sm">
                <%= for text <- [
                gettext("Everything in Free"),
                gettext("15 AI recipe generations / month"),
                gettext("4 AI meal plan generations / month"),
                gettext("Priority support")
              ] do %>
                  <li class="flex items-center gap-2 text-parchment">
                    <svg
                      class="h-3.5 w-3.5 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2.5"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    {text}
                  </li>
                <% end %>
              </ul>
              <a
                href={"/#{@current_language}/upgrade"}
                class="block w-full rounded-lg border border-paprika/60 py-2 text-center text-sm font-semibold text-paprika-soft transition-colors hover:border-paprika hover:text-parchment"
              >
                {gettext("Upgrade to Mehungry Plus")}
              </a>
            </div>

            <%!-- Pro / Nutritionist --%>
            <div class="rounded-2xl border border-ink-panel2 bg-ink-panel p-6">
              <h3 class="mb-1 text-base font-semibold text-parchment">Pro</h3>
              <p class="mb-1 text-xs font-medium text-basil">{gettext("For nutritionists")}</p>
              <div class="mb-1 flex items-baseline gap-1">
                <span class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                  €59
                </span>
                <span class="text-sm text-parchment-dim">{gettext("/month")}</span>
              </div>
              <p class="mb-5 text-xs text-parchment-dim">{gettext("or €599/yr")}</p>
              <ul class="mb-6 space-y-2.5 text-sm">
                <%= for text <- [
                gettext("Everything in Mehungry Plus"),
                gettext("30 AI recipe generations / month"),
                gettext("10 AI meal plans / month"),
                gettext("Full client management portal"),
                gettext("Appointment calendar")
              ] do %>
                  <li class="flex items-center gap-2 text-parchment">
                    <svg
                      class="h-3.5 w-3.5 shrink-0 text-basil-soft"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                      aria-hidden="true"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2.5"
                        d="M5 13l4 4L19 7"
                      />
                    </svg>
                    {text}
                  </li>
                <% end %>
              </ul>
              <a
                href={"/#{@current_language}/upgrade"}
                class="block w-full rounded-lg border border-basil/40 py-2 text-center text-sm font-medium text-basil transition-colors hover:border-basil hover:text-basil-soft"
              >
                {gettext("Explore Pro")}
              </a>
            </div>
          </div>

          <p class="mt-6 text-center text-xs text-parchment-dim">
            {gettext("Payments processed securely by Stripe. Cancel any subscription anytime.")}
          </p>
        </div>
      </section>

      <%!-- ══════════════════════════════════ BOTTOM CTA ══════════════════════════════════════════════════ --%>
      <section class="bg-gradient-to-b from-ink-panel to-ink py-24" aria-labelledby="cta-heading">
        <div class="mx-auto max-w-2xl px-4 text-center sm:px-6">
          <h2 id="cta-heading" class="mb-4 font-display text-4xl font-medium text-parchment">
            {gettext("Start tracking what actually matters.")}
          </h2>
          <p class="mb-8 text-parchment-dim">
            {gettext(
              "Join free. No credit card. Access the full nutrition database and start building recipes today."
            )}
          </p>
          <a
            href="/register"
            class="inline-block rounded-lg bg-paprika px-9 py-3.5 text-base font-bold text-ink shadow-lg shadow-black/30 transition-all hover:bg-paprika-soft"
          >
            {gettext("Create your free account →")}
          </a>
        </div>
      </section>

      <%!-- ══════════════════════════════════ FOOTER ═══════════════════════════════════════════════════════ --%>
      <footer class="border-t border-ink-panel2 bg-ink py-10" aria-label="Site footer">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="flex flex-col items-center justify-between gap-6 sm:flex-row">
            <div>
              <.get_logo id="footer-logo" class="mb-1 h-6 w-auto" show_tagline />
              <p class="text-xs text-parchment-dim">{gettext("Know what's on your plate.")}</p>
            </div>
            <nav class="flex gap-8 text-sm text-parchment-dim" aria-label="Footer navigation">
              <a
                href={"/#{@current_language}/browse"}
                class="transition-colors hover:text-parchment"
              >
                {gettext("Browse")}
              </a>
              <a href="#pricing" class="transition-colors hover:text-parchment">
                {gettext("Pricing")}
              </a>
              <a href="/privacy_policy" class="transition-colors hover:text-parchment">
                {gettext("Privacy")}
              </a>
              <a
                href={"/#{@current_language}/feedback"}
                class="transition-colors hover:text-parchment"
              >
                {gettext("Feedback")}
              </a>
            </nav>
          </div>
          <div class="mt-8 border-t border-ink-panel2 pt-6 text-center text-xs text-parchment-dim/60">
            {gettext("© 2025 M3Hungry. Nutrition data from USDA FoodData Central.")}
          </div>
        </div>
      </footer>
    </div>
    """
  end
end
