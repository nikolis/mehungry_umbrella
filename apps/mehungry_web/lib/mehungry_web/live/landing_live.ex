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

    # Feature a real published nutritionist profile in the hero when one exists;
    # the hero falls back to an honest "your profile" preview when none is public.
    featured_professional =
      Mehungry.Professionals.list_public_professionals() |> List.first()

    {:ok,
     assign(socket,
       page_title: gettext("M3Hungry — Grow Your Nutrition Practice"),
       page_description:
         gettext(
           "A discoverable public profile, a workspace for your clients and appointments, a literature assistant that hands you graded PubMed evidence, and AI that drafts meal plans backed by USDA FoodData Central — you review, adjust, and approve. The judgment stays 100% yours."
         ),
       recipe: recipe,
       recipes: recipes,
       featured_professional: featured_professional,
       # Honest, verifiable counts for the trust strip + literature section.
       ingredient_count: Mehungry.Food.count_ingredients(),
       research_condition_count: Mehungry.Literature.count_conditions_with_research(),
       analyzed_study_count: Mehungry.Literature.count_analyzed_studies(),
       # The real evidence-grading scheme the literature assistant applies.
       research_buckets: Mehungry.Literature.ResearchType.buckets(),
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
        where: (is_nil(r.private) or not r.private) and fragment("? <> '{}'::jsonb", r.nutrients),
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
            <a href="#literature" class="text-parchment-dim transition-colors hover:text-parchment">
              {gettext("Literature assistant")}
            </a>
            <a href="#practice" class="text-parchment-dim transition-colors hover:text-parchment">
              {gettext("The practice")}
            </a>
            <a href="#difference" class="text-parchment-dim transition-colors hover:text-parchment">
              {gettext("Why switch")}
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
              {gettext("For nutritionists & dietitians")}
            </div>

            <%!-- Headline --%>
            <h1
              id="hero-heading"
              class="mb-5 font-display text-5xl font-medium leading-[1.1] tracking-tight text-parchment sm:text-6xl md:text-7xl"
            >
              {gettext("Grow your nutrition practice.")}
              <em class="not-italic text-paprika-soft">{gettext("Keep it 100% yours.")}</em>
            </h1>

            <p class="mb-9 text-lg leading-relaxed text-parchment-dim sm:text-xl">
              {gettext(
                "A discoverable profile that brings clients in, one workspace for their records and appointments, a literature assistant that hands you the evidence, and AI that drafts the busywork — you review, adjust, approve."
              )}
            </p>

            <div class="flex flex-col items-center justify-center gap-3 sm:flex-row">
              <a
                href="/register"
                class="w-full rounded-lg bg-paprika px-8 py-3 text-base font-bold text-ink shadow-lg shadow-black/30 transition-all hover:bg-paprika-soft sm:w-auto"
              >
                {gettext("Start your practice")}
              </a>
              <a
                href={"/#{@current_language}/nutritionists"}
                class="w-full rounded-lg border border-ink-panel2 px-8 py-3 text-base font-medium text-parchment-dim transition-all hover:border-parchment-dim hover:text-parchment sm:w-auto"
              >
                {gettext("See a nutritionist profile →")}
              </a>
            </div>

            <%!-- Trust strip — only honest, verifiable claims --%>
            <div
              class="mt-12 flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-sm text-parchment-dim"
              aria-label="Key facts"
            >
              <span class="flex items-center gap-1.5">
                <.check_icon />
                <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                  {fmt_count(@ingredient_count)}
                </span>
                {gettext("foods in the database")}
              </span>
              <span class="flex items-center gap-1.5">
                <.check_icon />
                <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">168</span>
                {gettext("nutrients tracked per food")}
              </span>
              <span class="flex items-center gap-1.5">
                <.check_icon /> {gettext("Literature assistant built in")}
              </span>
            </div>
          </div>

          <%!-- Hero visual: public profile + practice workspace preview --%>
          <div class="relative mx-auto mt-16 max-w-2xl">
            <div class="overflow-hidden rounded-2xl border border-ink-panel2 bg-ink-panel/80 shadow-2xl shadow-black/40">
              <%!-- Browser chrome --%>
              <div class="flex items-center gap-1.5 border-b border-ink-panel2 bg-ink-panel px-4 py-3">
                <span class="h-2.5 w-2.5 rounded-full bg-red-500/60" aria-hidden="true"></span>
                <span class="h-2.5 w-2.5 rounded-full bg-yellow-500/60" aria-hidden="true"></span>
                <span class="h-2.5 w-2.5 rounded-full bg-green-500/60" aria-hidden="true"></span>
                <span class="ml-3 truncate text-xs text-parchment-dim">
                  m3hungry.com/nutritionists<%= if @featured_professional && @featured_professional.slug do %>/{@featured_professional.slug}<% end %>
                </span>
              </div>

              <div class="space-y-4 p-5">
                <%!-- Public profile row (real nutritionist when one is published) --%>
                <div class="flex items-center gap-4">
                  <%= if @featured_professional && @featured_professional.photo_url do %>
                    <img
                      src={@featured_professional.photo_url}
                      alt={profile_display_name(@featured_professional)}
                      class="h-14 w-14 rounded-full object-cover ring-2 ring-basil/30"
                      loading="lazy"
                    />
                  <% else %>
                    <div
                      class="flex h-14 w-14 items-center justify-center rounded-full bg-gradient-to-br from-paprika to-basil font-display text-lg font-bold text-ink"
                      aria-hidden="true"
                    >
                      {profile_initials(@featured_professional)}
                    </div>
                  <% end %>
                  <div class="min-w-0">
                    <p class="truncate font-display font-medium text-parchment">
                      {profile_display_name(@featured_professional)}
                    </p>
                    <p class="truncate text-sm text-parchment-dim">
                      {profile_tagline(@featured_professional)}
                    </p>
                  </div>
                </div>

                <%!-- The real workspace surfaces (capabilities, not vanity metrics) --%>
                <div class="flex flex-wrap gap-2">
                  <%= for chip <- [
                    gettext("Booking"),
                    gettext("Client records"),
                    gettext("Literature assistant"),
                    gettext("Articles"),
                    gettext("Payouts")
                  ] do %>
                    <span class="rounded-full border border-ink-panel2 bg-black/20 px-2.5 py-1 text-xs text-parchment-dim">
                      {chip}
                    </span>
                  <% end %>
                </div>

                <%!-- Practice dashboard preview (illustrative UI — not live figures) --%>
                <div class="grid grid-cols-2 gap-2 border-t border-ink-panel2 pt-4" aria-hidden="true">
                  <div class="rounded-xl border border-ink-panel2 bg-ink p-3">
                    <p class="text-xs text-parchment-dim">{gettext("Today's appointments")}</p>
                    <p class="mt-1 font-display text-xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                      3
                    </p>
                  </div>
                  <div class="rounded-xl border border-ink-panel2 bg-ink p-3">
                    <p class="text-xs text-parchment-dim">{gettext("Active clients")}</p>
                    <p class="mt-1 font-display text-xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                      18
                    </p>
                  </div>
                  <div class="col-span-2 rounded-xl border border-ink-panel2 bg-ink p-3">
                    <p class="mb-2 text-xs text-parchment-dim">{gettext("Saved research notes")}</p>
                    <div class="flex items-center gap-2">
                      <div class="h-2 flex-1 overflow-hidden rounded-full bg-ink-panel2">
                        <div class="h-full w-3/5 rounded-full bg-basil"></div>
                      </div>
                      <span class="text-xs text-parchment-dim [font-variant-numeric:tabular-nums]">
                        12
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Floating badge: the spine of the pitch --%>
            <div class="absolute -right-2 -top-3 hidden rounded-xl border border-paprika/30 bg-ink-panel px-3 py-2 shadow-lg sm:block">
              <p class="text-xs font-bold text-paprika-soft">{gettext("100% your judgment")}</p>
              <p class="text-xs text-parchment-dim">{gettext("AI & evidence assist · you decide")}</p>
            </div>

            <p class="mt-3 text-center text-xs text-parchment-dim/60">
              {gettext("Example dashboard — your practice once you're set up")}
            </p>
          </div>
        </div>
      </section>

      <%!-- ══════════════════ LITERATURE ASSISTANT — signature section ══════════════════════════════════ --%>
      <section
        id="literature"
        class="border-y border-ink-panel2 bg-ink py-24"
        aria-labelledby="literature-heading"
        style="scroll-margin-top: 4rem;"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-14 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-basil">
              {gettext("Literature assistant")}
            </p>
            <h2
              id="literature-heading"
              class="font-display text-4xl font-medium text-parchment sm:text-5xl"
            >
              {gettext("The evidence, graded.")}
              <span class="text-paprika-soft">{gettext("The conclusion, yours.")}</span>
            </h2>
            <p class="mx-auto mt-4 max-w-2xl text-parchment-dim">
              {gettext(
                "Search PubMed by condition and get results ranked by study quality — meta-analyses first, then trials, then cohorts. Read the full text in-app with the key claims highlighted. Save what matters as your own notes. We do the legwork; the judgment stays with you."
              )}
            </p>

            <%!-- Real proof numbers — only shown once research is actually digested --%>
            <%= if @analyzed_study_count > 0 do %>
              <p class="mt-5 text-sm text-parchment-dim">
                <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                  {fmt_count(@analyzed_study_count)}
                </span>
                {gettext("papers digested")}
                <%= if @research_condition_count > 0 do %>
                  &nbsp;·&nbsp;
                  <span class="font-bold text-basil [font-variant-numeric:tabular-nums]">
                    {fmt_count(@research_condition_count)}
                  </span>
                  {gettext("conditions covered")}
                <% end %>
              </p>
            <% end %>
          </div>

          <div class="grid grid-cols-1 items-start gap-10 md:grid-cols-2">
            <%!-- The evidence ladder — rendered from the REAL grading scheme --%>
            <div aria-label="Evidence hierarchy — example results">
              <p class="mb-4 text-xs font-medium uppercase tracking-wide text-parchment-dim">
                {gettext("Ranked by study quality")}
              </p>
              <div class="space-y-2">
                <%= for {_key, label, order} <- @research_buckets do %>
                  <div
                    class={[
                      "rounded-lg border px-4 py-2.5 text-sm transition-colors",
                      if(order == 1,
                        do: "border-paprika/40 bg-paprika/10 text-parchment",
                        else: "border-ink-panel2 bg-black/20 text-parchment-dim"
                      )
                    ]}
                    style={"width: #{100 - (order - 1) * 6}%; min-width: 55%;"}
                  >
                    <div class="flex items-center justify-between gap-3">
                      <span class={if(order == 1, do: "font-medium", else: "")}>{label}</span>
                      <%= if order == 1 do %>
                        <span class="shrink-0 rounded-full border border-paprika/40 px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-paprika-soft">
                          {gettext("Strongest")}
                        </span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
              <p class="mt-3 text-xs text-parchment-dim/60">
                {gettext("The same evidence hierarchy the search groups results into.")}
              </p>
            </div>

            <%!-- The workflow: search → read → save → resurface --%>
            <div>
              <p class="mb-4 text-xs font-medium uppercase tracking-wide text-parchment-dim">
                {gettext("How it works")}
              </p>
              <ol class="space-y-3">
                <%= for {step, text} <- [
                  {1, gettext("Search by condition — ulcerative colitis, PCOS, IBS…")},
                  {2, gettext("Read the full text in-app, with the key claims highlighted")},
                  {3, gettext("Save what matters as your own note — or write your own")},
                  {4, gettext("It resurfaces on the client who has that condition")}
                ] do %>
                  <li class="flex items-start gap-3 rounded-xl border border-ink-panel2 bg-ink-panel p-4">
                    <span class="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-basil/20 bg-basil/10 text-sm font-bold text-basil [font-variant-numeric:tabular-nums]">
                      {step}
                    </span>
                    <span class="text-sm text-parchment">{text}</span>
                  </li>
                <% end %>
              </ol>
              <p class="mt-4 text-sm text-parchment-dim">
                {gettext(
                  "No fabricated verdicts on conditions — we surface the evidence and its provenance. You reach the conclusion, and it stays defensibly yours."
                )}
              </p>
            </div>
          </div>

          <div class="mt-12 text-center">
            <a
              href="/register"
              class="inline-block rounded-lg bg-paprika px-8 py-3 text-base font-bold text-ink shadow-lg shadow-black/30 transition-all hover:bg-paprika-soft"
            >
              {gettext("See the literature assistant →")}
            </a>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════ POINT-OF-CARE LOOP ════════════════════════════════════════════════════ --%>
      <section id="loop" class="bg-ink-panel py-24" aria-labelledby="loop-heading">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="grid grid-cols-1 items-center gap-12 md:grid-cols-2">
            <div>
              <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-basil">
                {gettext("Point of care")}
              </p>
              <h2 id="loop-heading" class="mb-4 font-display text-4xl font-medium text-parchment">
                {gettext("Your notes find your client.")}
              </h2>
              <p class="mb-6 text-parchment-dim">
                {gettext(
                  "Link a client to the conditions they live with. The notes you saved from the literature show up right there — your words, your judgment, at the moment you need them."
                )}
              </p>
              <ul class="space-y-3 text-sm text-parchment">
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("A client file that holds dietary history, visits, and conditions")}
                </li>
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("Intake does the arithmetic — BMI, BMR, and TDEE calculated for you")}
                </li>
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("Import an existing history from a spreadsheet in one pass")}
                </li>
              </ul>
              <a
                href="#literature"
                class="mt-8 inline-flex items-center gap-1 text-sm font-semibold text-paprika-soft transition-colors hover:text-paprika"
              >
                {gettext("See where the notes come from →")}
              </a>
            </div>

            <%!-- Illustrative: a condition chip on a client card surfacing a saved note --%>
            <div
              class="rounded-2xl border border-ink-panel2 bg-ink p-5"
              aria-label="Client record with surfaced research note — example"
            >
              <div class="flex items-center gap-3 border-b border-ink-panel2 pb-4">
                <div
                  class="flex h-10 w-10 items-center justify-center rounded-full bg-paprika/10 font-bold text-paprika"
                  aria-hidden="true"
                >
                  MK
                </div>
                <div>
                  <p class="font-display font-medium text-parchment">{gettext("Client file")}</p>
                  <p class="text-xs text-parchment-dim">{gettext("Dietary history · Visits")}</p>
                </div>
              </div>
              <div class="mt-4">
                <p class="mb-2 text-xs text-parchment-dim">{gettext("Conditions")}</p>
                <div class="flex flex-wrap gap-2">
                  <span class="rounded-md border border-paprika/30 bg-paprika/10 px-2.5 py-1 text-xs text-paprika-soft">
                    {gettext("Ulcerative colitis")}
                  </span>
                  <span class="rounded-md border border-ink-panel2 bg-black/20 px-2.5 py-1 text-xs text-parchment-dim">
                    {gettext("Iron deficiency")}
                  </span>
                </div>
              </div>
              <div class="mt-4 rounded-xl border border-basil/20 bg-basil/5 p-4">
                <p class="mb-1 text-xs font-medium text-basil">{gettext("Your saved note")}</p>
                <p class="text-sm text-parchment">
                  {gettext("\"Low-residue during flares; reintroduce fibre gradually in remission.\"")}
                </p>
                <p class="mt-2 text-xs text-parchment-dim/60">
                  {gettext("Saved from a 2021 systematic review · your words")}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════ THE COMPLETE PRACTICE ═════════════════════════════════════════════════ --%>
      <section
        id="practice"
        class="border-y border-ink-panel2 bg-ink py-24"
        aria-labelledby="practice-heading"
        style="scroll-margin-top: 4rem;"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-14 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
              {gettext("The complete practice")}
            </p>
            <h2 id="practice-heading" class="font-display text-4xl font-medium text-parchment sm:text-5xl">
              {gettext("Everything in one place.")}
            </h2>
            <p class="mx-auto mt-4 max-w-xl text-parchment-dim">
              {gettext(
                "One platform runs the whole practice — from getting found, to the first appointment, to the evidence behind every plan."
              )}
            </p>
          </div>

          <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
            <%= for {title, body} <- [
              {gettext("Discoverable profile"), gettext("A public, SEO-indexed profile and directory so clients searching your city find you.")},
              {gettext("Online booking"), gettext("Set your weekly availability; clients request, you accept, and a calendar invite goes out.")},
              {gettext("Client records"), gettext("A dietary-history file per client — intake, visits, conditions, weight trend.")},
              {gettext("Literature assistant"), gettext("Graded PubMed research per condition, saved as your own notes.")},
              {gettext("Published articles"), gettext("Write evidence-referenced articles that rank and build your authority.")}
            ] do %>
              <div class="rounded-xl border border-ink-panel2 bg-ink-panel p-6 transition-colors hover:border-paprika/40">
                <div class="mb-4 flex h-10 w-10 items-center justify-center rounded-lg border border-basil/20 bg-basil/10">
                  <.check_icon class="h-5 w-5 text-basil" />
                </div>
                <h3 class="mb-2 font-display font-medium text-parchment">{title}</h3>
                <p class="text-sm text-parchment-dim">{body}</p>
              </div>
            <% end %>
          </div>

          <div class="mt-10 text-center">
            <a
              href={"/#{@current_language}/nutritionists"}
              class="rounded-lg border border-ink-panel2 px-6 py-2.5 text-sm font-medium text-parchment-dim transition-all hover:border-parchment-dim hover:text-parchment"
            >
              {gettext("See a live profile →")}
            </a>
          </div>
        </div>
      </section>

      <%!-- ══════════════════════════════════ AI DRAFTS, YOU APPROVE ═════════════════════════════════════ --%>
      <section
        class="bg-ink-panel/50 py-24"
        aria-labelledby="ai-heading"
      >
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="grid grid-cols-1 items-center gap-12 md:grid-cols-2">
            <%!-- Interface demo — labeled as example to avoid misleading --%>
            <div class="order-2 md:order-1" aria-label="AI drafting interface example">
              <div class="overflow-hidden rounded-2xl border border-ink-panel2 bg-ink p-5">
                <div class="mb-4 flex items-center gap-2">
                  <span
                    class="h-2 w-2 rounded-full bg-paprika animate-pulse"
                    aria-hidden="true"
                  ></span>
                  <span class="text-xs text-parchment-dim">{gettext("AI draft — for your review")}</span>
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
                    {gettext("Review & approve →")}
                  </p>
                </div>

                <p class="mt-3 text-center text-xs text-parchment-dim/60">
                  {gettext("Example output — your results will vary by request")}
                </p>
              </div>
            </div>

            <div class="order-1 md:order-2">
              <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
                {gettext("AI-assisted")}
              </p>
              <h2 id="ai-heading" class="mb-4 font-display text-4xl font-medium text-parchment">
                {gettext("Draft the busywork. You keep the final say.")}
              </h2>
              <p class="mb-6 text-parchment-dim">
                {gettext(
                  "Describe a client's goal, a cuisine, a constraint. The AI drafts a complete recipe or weekly plan with every ingredient mapped to the USDA database — then you review, adjust, and approve before anything reaches a client."
                )}
              </p>
              <ul class="space-y-3 text-sm text-parchment">
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("Recipes drafted to your calorie and macro targets")}
                </li>
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("Every ingredient mapped to USDA FoodData Central — exact, not estimated")}
                </li>
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("A full weekly meal plan in one request")}
                </li>
                <li class="flex items-start gap-2.5">
                  <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                  {gettext("Nothing is published until you approve it")}
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
                  {gettext("Included in the Pro plan")}
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      <%!-- ══════════════════ USDA DEPTH — credibility proof-point ══════════════════════════════════════ --%>
      <section class="bg-ink py-24" aria-labelledby="proof-heading">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-14 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-basil">
              {gettext("Backed by USDA data")}
            </p>
            <h2 id="proof-heading" class="font-display text-4xl font-medium text-parchment">
              {gettext("Every plan is backed by real data —")}
              <span class="text-basil [font-variant-numeric:tabular-nums]">168</span>
              {gettext("nutrients, not estimates.")}
            </h2>
            <p class="mx-auto mt-4 max-w-xl text-parchment-dim">
              {gettext(
                "Most trackers give you calories and macros. Every recipe here is built from real USDA ingredients, so the nutrition is exact — the same data nutritionists and researchers actually use."
              )}
            </p>
          </div>

          <div class="grid grid-cols-1 items-start gap-6 md:grid-cols-2">
            <%!-- Nutrient depth comparison --%>
            <div class="space-y-4">
              <div class="rounded-2xl border border-ink-panel2 bg-black/20 p-6">
                <p class="mb-4 text-sm font-medium text-parchment-dim">
                  {gettext("What most apps track")}
                </p>
                <div class="flex flex-wrap gap-2">
                  <%= for nutrient <- ["Calories", "Protein", "Carbohydrates", "Total Fat"] do %>
                    <span class="rounded-lg bg-ink-panel2/50 px-3 py-1.5 text-xs text-parchment-dim">
                      {nutrient}
                    </span>
                  <% end %>
                  <span class="px-2 py-1.5 text-xs text-parchment-dim/50">
                    {gettext("… and that's it")}
                  </span>
                </div>
              </div>

              <div class="rounded-2xl border border-basil/20 bg-ink-panel p-6 ring-1 ring-basil/10">
                <p class="mb-4 text-sm font-medium text-basil">{gettext("What M3Hungry tracks")}</p>
                <div class="flex flex-wrap gap-1.5">
                  <%= for nutrient <- [
                    "Dietary Fiber", "Saturated Fat", "MUFA", "Linoleic acid",
                    "DHA 22:6 n-3", "Vitamin K", "Folate", "Selenium"
                  ] do %>
                    <span class="rounded-lg border border-basil/15 bg-basil/10 px-3 py-1.5 text-xs text-parchment">
                      {nutrient}
                    </span>
                  <% end %>
                  <span class="rounded-lg border border-dashed border-basil/20 px-3 py-1.5 text-xs font-medium text-basil">
                    + <span class="font-bold [font-variant-numeric:tabular-nums]">156</span>
                    {gettext("more")}
                  </span>
                </div>
              </div>
            </div>

            <%!-- Meal-planning demo: recipe card + nutrition chart --%>
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

      <%!-- ══════════════ CONSUMER RING — the platform your clients use (demoted) ═══════════════════════ --%>
      <section class="border-y border-ink-panel2 bg-ink-panel py-24" aria-labelledby="discover-heading">
        <div class="mx-auto max-w-6xl px-4 sm:px-6">
          <div class="mb-12 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-parchment-dim">
              {gettext("The platform your clients use")}
            </p>
            <h2 id="discover-heading" class="font-display text-4xl font-medium text-parchment">
              {gettext("A consumer app your clients already want.")}
            </h2>
            <p class="mx-auto mt-4 max-w-xl text-parchment-dim">
              {gettext(
                "Your clients log food, plan their week, and browse recipes — each built with real USDA ingredients, so the nutrition facts are exact. The same platform you work in."
              )}
            </p>
          </div>

          <%!-- Real recipe cards from DB --%>
          <%= if length(@recipes) > 0 do %>
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
              <%= for recipe <- Enum.take(@recipes, 3) do %>
                <a
                  href={"/#{@current_language}/browse/#{recipe.id}"}
                  class="group overflow-hidden rounded-xl border border-ink-panel2 bg-ink transition-all hover:border-basil/30 hover:shadow-lg hover:shadow-black/20 focus-visible:outline focus-visible:outline-2 focus-visible:outline-paprika"
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
                        {recipe.servings} {gettext("servings")}
                        <%= if recipe.cooking_time_lower_limit do %>
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

      <%!-- ══════════════════ THE DIFFERENCE — contrast vs legacy software ═══════════════════════════════ --%>
      <section
        id="difference"
        class="bg-ink py-24"
        aria-labelledby="difference-heading"
        style="scroll-margin-top: 4rem;"
      >
        <div class="mx-auto max-w-5xl px-4 sm:px-6">
          <div class="mb-12 text-center">
            <p class="mb-3 text-xs font-semibold uppercase tracking-widest text-basil">
              {gettext("The difference")}
            </p>
            <h2
              id="difference-heading"
              class="font-display text-4xl font-medium text-parchment sm:text-5xl"
            >
              {gettext("Not another practice manager.")}
              <em class="not-italic text-paprika-soft">{gettext("An evidence engine.")}</em>
            </h2>
            <p class="mx-auto mt-4 max-w-2xl text-parchment-dim">
              {gettext(
                "Conventional nutrition software runs your schedule, your notes, and your billing. m3hungry does that too — then adds the layer they leave out: living, graded science wired straight into the client in front of you."
              )}
            </p>
          </div>

          <%!-- Column headers (desktop only) --%>
          <div class="hidden grid-cols-[1.1fr_1fr_1fr] gap-4 px-5 sm:grid">
            <div></div>
            <p class="text-xs font-semibold uppercase tracking-widest text-parchment-dim">
              {gettext("Conventional software")}
            </p>
            <p class="text-xs font-semibold uppercase tracking-widest text-paprika-soft">
              {gettext("m3hungry")}
            </p>
          </div>

          <div class="mt-3 space-y-3 sm:space-y-0">
            <%= for {dimension, them, us} <- [
              {gettext("The science"),
               gettext("A static library of condition handouts, written once."),
               gettext("Live PubMed research, ranked by study quality and cited to the paper — updated as the evidence moves.")},
              {gettext("At the point of care"),
               gettext("Research and client records sit in separate tabs."),
               gettext("The notes you saved surface on the exact client who has that condition.")},
              {gettext("Getting found"),
               gettext("A closed workspace — you bring your own clients."),
               gettext("A public, SEO-indexed profile and directory that brings clients to you.")},
              {gettext("Meal plans"),
               gettext("Copy-paste templates you adapt by hand."),
               gettext("AI drafts a first plan from USDA data; you review, adjust, approve.")},
              {gettext("Commitment"),
               gettext("A four-figure up-front licence."),
               gettext("Free for a month, then €29.90 — cancel anytime.")}
            ] do %>
              <div class="grid grid-cols-1 overflow-hidden rounded-xl border border-ink-panel2 sm:grid-cols-[1.1fr_1fr_1fr] sm:rounded-none sm:border-x-0 sm:border-t-0 sm:border-b sm:border-ink-panel2">
                <div class="bg-ink-panel px-5 py-4 sm:bg-transparent">
                  <p class="font-display font-medium text-parchment">{dimension}</p>
                </div>
                <div class="border-t border-ink-panel2 bg-ink-panel px-5 py-4 sm:border-0 sm:bg-transparent">
                  <p class="flex items-start gap-2.5 text-sm text-parchment-dim">
                    <span
                      class="mt-2 h-1 w-3 shrink-0 rounded-full bg-parchment-dim/30"
                      aria-hidden="true"
                    >
                    </span>
                    {them}
                  </p>
                </div>
                <div class="border-t border-ink-panel2 bg-paprika/5 px-5 py-4 sm:border-0">
                  <p class="flex items-start gap-2.5 text-sm text-parchment">
                    <.check_icon class="mt-0.5 h-4 w-4 shrink-0 text-basil-soft" />
                    {us}
                  </p>
                </div>
              </div>
            <% end %>
          </div>

          <p class="mx-auto mt-10 max-w-xl text-center text-sm text-parchment-dim/70">
            {gettext(
              "The schedule, the records, the billing — table stakes. The evidence engine is why you switch."
            )}
          </p>
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

            <%!-- Pro / Nutritionist — most popular --%>
            <div class="relative rounded-2xl border-2 border-paprika bg-ink-panel p-6 shadow-xl shadow-black/20">
              <div class="absolute -top-3 left-1/2 -translate-x-1/2 rounded-full bg-paprika px-3 py-0.5 text-xs font-bold text-ink">
                {gettext("Most popular")}
              </div>
              <h3 class="mb-1 text-base font-semibold text-parchment">Pro</h3>
              <p class="mb-1 text-xs font-medium text-basil">{gettext("For nutritionists")}</p>
              <div class="mb-1 flex items-baseline gap-1">
                <span class="text-3xl font-bold text-basil [font-variant-numeric:tabular-nums]">
                  €29.90
                </span>
                <span class="text-sm text-parchment-dim">{gettext("/month")}</span>
              </div>
              <p class="mb-5 text-xs text-parchment-dim">{gettext("or €290/yr")}</p>
              <ul class="mb-6 space-y-2.5 text-sm">
                <%= for text <- [
                gettext("Everything in Mehungry Plus"),
                gettext("30 AI recipe generations / month"),
                gettext("10 AI meal plans / month"),
                gettext("Literature assistant + research notes"),
                gettext("Client records & dietary history"),
                gettext("Booking & appointment calendar")
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
                {gettext("Explore Pro")}
              </a>
            </div>

            <%!-- Plus --%>
            <div class="rounded-2xl border border-ink-panel2 bg-ink-panel p-6">
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
                class="block w-full rounded-lg border border-basil/40 py-2 text-center text-sm font-medium text-basil transition-colors hover:border-basil hover:text-basil-soft"
              >
                {gettext("Upgrade to Mehungry Plus")}
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
            {gettext("Build a practice that's unmistakably yours.")}
          </h2>
          <p class="mb-8 text-parchment-dim">
            {gettext(
              "Join free. No credit card. Get a profile, the literature assistant, and a workspace for your clients today."
            )}
          </p>
          <a
            href="/register"
            class="inline-block rounded-lg bg-paprika px-9 py-3.5 text-base font-bold text-ink shadow-lg shadow-black/30 transition-all hover:bg-paprika-soft"
          >
            {gettext("Start your practice →")}
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
            <nav
              class="flex flex-wrap justify-center gap-x-6 gap-y-3 text-sm text-parchment-dim sm:gap-8"
              aria-label="Footer navigation"
            >
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
              <a href="/terms" class="transition-colors hover:text-parchment">
                {gettext("Terms")}
              </a>
              <a href="/cookies" class="transition-colors hover:text-parchment">
                {gettext("Cookies")}
              </a>
              <a href="/legal" class="transition-colors hover:text-parchment">
                {gettext("Legal Notice")}
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
            {gettext("© 2026 M3Hungry. Nutrition data from USDA FoodData Central.")}
          </div>
        </div>
      </footer>
    </div>
    """
  end

  # ── Small presentational helpers ────────────────────────────────────────────

  attr :class, :string, default: "h-4 w-4 text-basil-soft"

  # The checkmark used across feature lists and the trust strip.
  defp check_icon(assigns) do
    ~H"""
    <svg class={@class} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
    </svg>
    """
  end

  # Group digits into thousands with commas (e.g. 12345 → "12,345").
  defp fmt_count(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp fmt_count(_), do: "0"

  # ── Hero profile helpers ────────────────────────────────────────────────────
  # Fall back to an honest "your profile" template when no public nutritionist
  # exists yet, so the hero never invents a fake person.

  defp profile_display_name(%{display_name: name}) when is_binary(name) and name != "",
    do: name

  defp profile_display_name(_), do: gettext("Your name here")

  defp profile_tagline(profile) when is_map(profile) do
    [Map.get(profile, :specialization), Map.get(profile, :city)]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> case do
      [] -> gettext("Registered nutritionist")
      parts -> Enum.join(parts, " · ")
    end
  end

  defp profile_tagline(_), do: gettext("Your specialization · your city")

  defp profile_initials(%{display_name: name}) when is_binary(name) and name != "" do
    name
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp profile_initials(_), do: "+"
end
