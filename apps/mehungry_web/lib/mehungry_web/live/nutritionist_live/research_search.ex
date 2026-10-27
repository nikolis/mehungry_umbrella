defmodule MehungryWeb.NutritionistLive.ResearchSearch do
  @moduledoc """
  Nutritionist **research search** landing (`/nutritionist/research`).

  A search box over the **full list of conditions** (`Literature.conditions_for_search/1`):
  the page loads with every condition listed, those with digested research ranked
  first and showing a study count; typing filters the list (fuzzy, by condition
  name). Picking a condition opens its grouped-by-research-type results
  (`ResearchCondition`) — one with no digested research yet shows an empty state
  there. This is a read-only surface over already-ingested, extractor-analyzed
  literature — nothing is crawled on demand.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Literature

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Research")
     |> assign(:query, "")
     |> assign(:catalog, Literature.conditions_for_search())}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, assign(socket, query: q, catalog: Literature.conditions_for_search(q))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <header class="mb-6">
        <div class="flex items-start justify-between gap-3">
          <h1 class="text-2xl font-semibold text-parchment">Research</h1>
          <.link
            navigate={~p"/nutritionist/research/notes"}
            class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment shrink-0"
          >
            <.icon name="hero-bookmark" class="w-4 h-4" /> My notes
          </.link>
        </div>
        <p class="text-sm text-parchment-dim mt-1">
          Search pre-digested, nutrition-relevant PubMed research by condition. Each result is a
          published study with its key findings highlighted and linked to the source.
        </p>
      </header>

      <form id="research-search-form" phx-change="search" class="mb-6">
        <div class="relative">
          <.icon
            name="hero-magnifying-glass"
            class="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-parchment-dim"
          />
          <input
            type="text"
            name="q"
            value={@query}
            phx-debounce="200"
            autocomplete="off"
            placeholder="Search a condition — e.g. Ulcerative Colitis"
            class="w-full pl-10 pr-4 py-2.5 rounded-xl bg-ink-panel2 border border-ink-panel2 text-parchment placeholder:text-parchment-dim focus:outline-none focus:border-basil"
          />
        </div>
      </form>

      <p :if={@catalog == []} class="text-sm text-parchment-dim py-8 text-center">
        <span :if={@query == ""}>No conditions available yet.</span>
        <span :if={@query != ""}>No conditions match “{@query}”.</span>
      </p>

      <ul class="space-y-2">
        <li :for={entry <- @catalog}>
          <.link
            navigate={~p"/nutritionist/research/#{entry.condition.id}"}
            class="flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-ink-panel2 hover:bg-ink-panel2/70 border border-transparent hover:border-basil/40 transition"
          >
            <span class="text-parchment font-medium">{entry.condition.name}</span>
            <span class="text-xs text-parchment-dim shrink-0">
              {entry.study_count} stud{if entry.study_count == 1, do: "y", else: "ies"}
            </span>
          </.link>
        </li>
      </ul>
    </div>
    """
  end
end
