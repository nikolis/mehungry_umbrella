defmodule MehungryWeb.NutritionistLive.ResearchSearch do
  @moduledoc """
  Nutritionist **research search** landing (`/nutritionist/research`) — dual-mode.

  - **Conditions** (default, fast path): a search box over the full condition list
    (`FactMining.conditions_for_search/1`); picking one opens its grouped results
    (`ResearchCondition`).
  - **All research** (global, deep path): a cross-condition full-text search over
    mined findings + paper titles/abstracts (`FactMining.search_all_research/2`),
    rendered as **one card per PMID** with a per-condition labelled row list — a
    finding-match outranks a title/abstract-only one (abstract-inclusive). Both
    modes share the one search box; a segmented toggle switches intent.

  Read-only over already-mined literature (the external biomed-fact-miner) —
  nothing is crawled on demand.
  """
  use MehungryWeb, :live_view

  import MehungryWeb.NutritionistLive.ResearchFormatting

  alias Mehungry.FactMining

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Research"))
     |> assign(:mode, :conditions)
     |> assign(:query, "")
     |> assign(:catalog, FactMining.conditions_for_search())
     |> assign(:results, [])
     # When a typo'd query returns nothing, we auto-retry a trigram-corrected
     # spelling and show `{original, corrected}` here as a "showing results for…".
     |> assign(:corrected, nil)}
  end

  @impl true
  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode = if mode == "papers", do: :papers, else: :conditions
    {:noreply, assign(socket, mode: mode) |> run_query(socket.assigns.query)}
  end

  # Both phx-change (typing) and phx-submit (Enter) route here — the submit
  # binding is what stops Enter from doing a native form submit that would reload
  # the page and reset the mode back to Conditions.
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, :query, q) |> run_query(q)}
  end

  # Run the active mode's query. Conditions filters the catalog by name; papers
  # runs the global cross-condition search (blank → no cards).
  defp run_query(%{assigns: %{mode: :conditions}} = socket, q),
    do: assign(socket, catalog: FactMining.conditions_for_search(q), corrected: nil)

  defp run_query(%{assigns: %{mode: :papers}} = socket, q) do
    case FactMining.search_all_research(q) do
      [] ->
        # Nothing matched — try a trigram-corrected spelling (e.g. a missing
        # letter) before giving up, and surface what we searched instead.
        case FactMining.spelling_suggestion(q) do
          nil ->
            assign(socket, results: [], corrected: nil)

          suggestion ->
            case FactMining.search_all_research(suggestion) do
              [] -> assign(socket, results: [], corrected: nil)
              results -> assign(socket, results: results, corrected: {String.trim(q), suggestion})
            end
        end

      results ->
        assign(socket, results: results, corrected: nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <header class="mb-5">
        <div class="flex items-start justify-between gap-3">
          <h1 class="text-2xl font-semibold text-parchment">{gettext("Research")}</h1>
          <.link
            navigate={~p"/nutritionist/research/notes"}
            class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment shrink-0"
          >
            <.icon name="hero-bookmark" class="w-4 h-4" /> {gettext("My notes")}
          </.link>
        </div>
        <p class="text-sm text-parchment-dim mt-1">
          {gettext(
            "Search pre-digested, nutrition-relevant PubMed research. Browse by condition, or search every condition at once for a substance or term."
          )}
        </p>
      </header>

      <%!-- Mode toggle: Conditions (fast path) vs All research (global). --%>
      <div
        class="inline-flex items-center gap-1 mb-4 p-1 rounded-xl bg-ink-panel2"
        role="tablist"
        aria-label={gettext("Search mode")}
      >
        <button
          :for={{key, label} <- [{:conditions, gettext("Conditions")}, {:papers, gettext("All research")}]}
          type="button"
          role="tab"
          aria-selected={to_string(@mode == key)}
          phx-click="set_mode"
          phx-value-mode={key}
          class={[
            "px-3 py-1.5 rounded-lg text-sm transition-colors",
            if(@mode == key,
              do: "bg-basil/15 text-basil font-medium",
              else: "text-parchment-dim hover:text-parchment"
            )
          ]}
        >
          {label}
        </button>
      </div>

      <form id="research-search-form" phx-change="search" phx-submit="search" class="mb-2">
        <div class="relative">
          <%!-- Magnifier (idle) swaps to a spinner while a search request is in
               flight. LiveView stamps phx-change-loading/phx-submit-loading on this
               form the instant the event is pushed and strips it when the diff
               lands — so this is the pending cue even though run_query is sync. --%>
          <.icon
            name="hero-magnifying-glass"
            class="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-parchment-dim phx-change-loading:hidden phx-submit-loading:hidden"
          />
          <svg
            viewBox="0 0 24 24"
            fill="none"
            aria-hidden="true"
            class="hidden phx-change-loading:block phx-submit-loading:block w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-basil animate-spin motion-reduce:animate-none"
          >
            <circle cx="12" cy="12" r="9" stroke="currentColor" stroke-width="2.5" class="opacity-25" />
            <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" />
          </svg>
          <input
            type="text"
            name="q"
            value={@query}
            phx-debounce="250"
            autocomplete="off"
            placeholder={
              if @mode == :papers,
                do: gettext("Search all research — e.g. curcumin, low-FODMAP"),
                else: gettext("Search a condition — e.g. Ulcerative Colitis")
            }
            class="w-full pl-10 pr-4 py-2.5 rounded-xl bg-ink-panel2 border border-ink-panel2 text-parchment placeholder:text-parchment-dim focus:outline-none focus:border-basil"
          />
          <%!-- Indeterminate sweep under the field — motion even on a fast query. --%>
          <span
            aria-hidden="true"
            class="hidden phx-change-loading:block phx-submit-loading:block absolute inset-x-0 -bottom-1 h-0.5 overflow-hidden rounded-full"
          >
            <span class="block h-full w-1/3 bg-basil animate-sweep motion-reduce:animate-none"></span>
          </span>
        </div>
      </form>

      <p :if={@mode == :papers} class="text-[11px] text-parchment-dim/80 mb-5">
        {gettext(
          "Searches distilled findings, titles, and abstracts across every condition — not full paper text."
        )}
      </p>
      <div :if={@mode == :conditions} class="mb-5"></div>

      <%!-- ── Conditions mode ──────────────────────────────────────────────── --%>
      <div :if={@mode == :conditions}>
        <p :if={@catalog == []} class="text-sm text-parchment-dim py-8 text-center">
          <span :if={@query == ""}>{gettext("No conditions available yet.")}</span>
          <span :if={@query != ""}>{gettext("No conditions match “%{query}”.", query: @query)}</span>
        </p>

        <ul class="space-y-2">
          <li :for={entry <- @catalog}>
            <.link
              navigate={~p"/nutritionist/research/#{entry.condition.id}"}
              class="flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-ink-panel2 hover:bg-ink-panel2/70 border border-transparent hover:border-basil/40 transition"
            >
              <span class="text-parchment font-medium">{entry.condition.name}</span>
              <span class="text-xs text-parchment-dim shrink-0">
                {ngettext("%{count} study", "%{count} studies", entry.study_count)}
              </span>
            </.link>
          </li>
        </ul>
      </div>

      <%!-- ── All-research mode (global, one card per PMID) ─────────────────── --%>
      <div :if={@mode == :papers} aria-live="polite">
        <p :if={@query == ""} class="text-sm text-parchment-dim py-8 text-center">
          {gettext("Type a term to search findings and abstracts across every condition.")}
        </p>

        <p :if={@query != "" and @results == []} class="text-sm text-parchment-dim py-8 text-center">
          {gettext(
            "No findings or abstracts mention “%{q}” in any condition. Full paper text isn't searchable — open papers on PubMed to check.",
            q: @query
          )}
        </p>

        <%!-- Auto-corrected a typo'd query — tell the nutritionist what we searched. --%>
        <p :if={@corrected} class="text-xs text-parchment-dim mb-3">
          {gettext("Showing results for")}
          <span class="text-parchment font-medium">“{elem(@corrected, 1)}”</span>
          — {gettext("searched for")} <span class="italic">“{elem(@corrected, 0)}”</span>
        </p>

        <p :if={@results != []} class="text-xs text-parchment-dim mb-3">
          {ngettext(
            "%{count} matching paper — best match first.",
            "%{count} matching papers — best match first.",
            length(@results)
          )}<span :if={length(@results) == 50}> {gettext("(showing the top 50)")}</span>
        </p>

        <.global_result_card :for={card <- @results} card={card} query={@query} />
      </div>
    </div>
    """
  end

  # One card per PMID: the paper, its match cue, and the per-condition rows it's
  # filed under — each row keeps its own verification label (never collapsed).
  attr :card, :map, required: true
  attr :query, :any, required: true

  defp global_result_card(assigns) do
    ~H"""
    <article class="mb-3 p-4 rounded-xl bg-ink-panel2 border border-ink-panel2">
      <a
        href={pubmed_url(@card)}
        target="_blank"
        rel="noopener"
        class="text-parchment font-medium hover:text-basil hover:underline"
      >
        <.highlighted text={@card.title || gettext("PMID %{pmid}", pmid: @card.pmid || "—")} query={@query} />
      </a>

      <p :if={authors_line(@card.authors)} class="text-xs text-parchment-dim mt-1">
        {authors_line(@card.authors)}
      </p>

      <div class="flex flex-wrap items-center gap-1.5 mt-2 text-[10px]">
        <span
          :if={@card.any_in_finding}
          class="px-2 py-0.5 rounded-full bg-basil/15 text-basil font-medium"
          title={gettext("Your term appears in a distilled finding of this paper.")}
        >
          {gettext("Matched in a finding")}
        </span>
        <span
          :if={not @card.any_in_finding}
          class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim"
          title={gettext("Your term appears only in this paper's abstract — no finding mentions it.")}
        >
          {gettext("Matched in abstract")}
        </span>
        <span
          :if={@card.medline?}
          class="px-2 py-0.5 rounded-full bg-basil/15 text-basil font-medium"
          title={gettext("Published in a MEDLINE-indexed journal.")}
        >
          {gettext("MEDLINE")}
        </span>
        <span :if={@card.journal} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
          {@card.journal}
        </span>
        <span :if={@card.publication_year} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
          {@card.publication_year}
        </span>
      </div>

      <%!-- Abstract snippet only when the match was abstract-only (no finding hit). --%>
      <p :if={@card.abstract_snippet} class="text-xs text-parchment-dim/80 italic mt-2 line-clamp-3">
        <.highlighted text={@card.abstract_snippet} query={@query} />
      </p>

      <%!-- Per-condition rows: the paper's findings under each condition it's filed
           under, verified-first, each keeping its own label. The chip deep-links to
           that condition's research page. --%>
      <ul class="mt-3 space-y-1.5 border-t border-ink pt-3">
        <li :for={c <- @card.conditions} class="text-xs flex flex-wrap items-baseline gap-x-1.5 gap-y-0.5">
          <.link
            navigate={~p"/nutritionist/research/#{c.condition_id}"}
            class="px-2 py-0.5 rounded-full bg-ink text-parchment hover:text-basil shrink-0"
          >
            {c.condition_name}
          </.link>
          <span class={label_class(c.label)}>{label_text(c.label)}</span>
          <span class="text-parchment-dim">·</span>
          <span class="text-parchment-dim min-w-0">
            <.highlighted text={c.finding_text} query={@query} />
          </span>
        </li>
      </ul>
    </article>
    """
  end
end
