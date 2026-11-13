defmodule MehungryWeb.NutritionistLive.ResearchCondition do
  @moduledoc """
  Nutritionist **research results** for one condition
  (`/nutritionist/research/:condition_id`).

  The source is the external **biomed-fact-miner** (`Mehungry.FactMining`): each
  condition's stored `ConditionMinedFact`s, grouped by publication. A publication
  whose source licence is `commercial_ok` is **presentable** — its card shows the
  distilled facts as claims *with* their verbatim quotes, grouped by research type
  (strongest evidence first). Everything else is a **free claim**: the nutritionist
  sees our distilled wording + the paper's verification label and a link to the
  original publication, but **no quote / no full text** (we don't hold the right to
  reproduce it).

  Every fact can be saved to the nutritionist's own notes (the per-fact Save
  toggle) or annotated with a custom note. Read-only otherwise.
  """
  use MehungryWeb, :live_view

  alias Mehungry.FactMining
  alias Mehungry.Health
  alias Mehungry.Professionals.ResearchNotes

  # Within-group ordering the nutritionist can pick. `:relevance` is the default
  # (MEDLINE-indexed → most recent — the context's own order).
  @sorts [
    relevance: "Best match",
    newest: "Newest first",
    findings: "Most findings"
  ]

  @impl true
  def mount(%{"condition_id" => condition_id}, _session, socket) do
    condition = Health.get_condition!(condition_id)
    research = FactMining.research_for_condition(condition.id)
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, condition.name)
     |> assign(:condition, condition)
     |> assign(:groups, research.groups)
     |> assign(:free_publications, research.free_publications)
     |> assign(:publication_count, research.publication_count)
     |> assign(:fact_count, research.fact_count)
     |> assign(:sort, :relevance)
     |> assign(:saved_keys, ResearchNotes.saved_claim_keys(user.id, condition.id))
     |> assign(:composing_study_id, nil)}
  end

  @impl true
  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, assign(socket, :sort, sort_key_atom(sort))}
  end

  # Save ⇄ unsave a fact (the per-fact bookmark toggle). `claim_id` carries the
  # miner `fact_id`; `study_id` is the enriched publication's study id.
  def handle_event("toggle_save", %{"study_id" => study_id, "claim_id" => fact_id}, socket) do
    study_id = String.to_integer(study_id)
    user = socket.assigns.current_user
    key = {study_id, fact_id}

    socket =
      if MapSet.member?(socket.assigns.saved_keys, key) do
        {:ok, _} = ResearchNotes.delete_suggested(user.id, study_id, fact_id)
        assign(socket, :saved_keys, MapSet.delete(socket.assigns.saved_keys, key))
      else
        case find_fact(socket, study_id, fact_id) do
          %{} = fact ->
            attrs =
              ResearchNotes.suggested_attrs_from_fact(socket.assigns.condition.id, study_id, fact)

            {:ok, _} = ResearchNotes.save_suggested(user.id, attrs)
            assign(socket, :saved_keys, MapSet.put(socket.assigns.saved_keys, key))

          nil ->
            socket
        end
      end

    {:noreply, socket}
  end

  # Reveal / dismiss the "write your own note" composer for one paper.
  def handle_event("compose_note", %{"study_id" => study_id}, socket) do
    {:noreply, assign(socket, :composing_study_id, String.to_integer(study_id))}
  end

  def handle_event("cancel_compose", _params, socket) do
    {:noreply, assign(socket, :composing_study_id, nil)}
  end

  def handle_event("save_custom", %{"study_id" => study_id, "body" => body}, socket) do
    body = String.trim(body)
    user = socket.assigns.current_user

    if body == "" do
      {:noreply,
       socket
       |> put_flash(:error, gettext("Write something first."))
       |> assign(:composing_study_id, nil)}
    else
      {:ok, _} =
        ResearchNotes.create_custom(user.id, %{
          condition_id: socket.assigns.condition.id,
          study_id: String.to_integer(study_id),
          body: body
        })

      {:noreply,
       socket
       |> assign(:composing_study_id, nil)
       |> put_flash(:info, gettext("Note saved to your notes."))}
    end
  end

  defp sort_key_atom(s), do: Enum.find(Keyword.keys(@sorts), &(to_string(&1) == s)) || :relevance

  defp sort_options do
    [
      relevance: gettext("Best match"),
      newest: gettext("Newest first"),
      findings: gettext("Most findings")
    ]
  end

  # Apply the chosen sort to each group's publications (no DB round-trip).
  defp sorted_groups(groups, sort) do
    Enum.map(groups, fn group ->
      %{group | publications: sort_publications(group.publications, sort)}
    end)
  end

  defp sort_publications(pubs, :newest),
    do: Enum.sort_by(pubs, &(-(&1.publication_year || -99_999)))

  defp sort_publications(pubs, :findings), do: Enum.sort_by(pubs, &(-length(&1.facts)))

  # :relevance — the context already sorts by MEDLINE → year; keep that order.
  defp sort_publications(pubs, _relevance), do: pubs

  # Locate a fact (by study_id + fact_id) within the loaded publications so a Save
  # can snapshot it server-side — never trusting a client-submitted body/quote.
  defp find_fact(socket, study_id, fact_id) do
    (Enum.flat_map(socket.assigns.groups, & &1.publications) ++ socket.assigns.free_publications)
    |> Enum.filter(&(&1.study_id == study_id))
    |> Enum.flat_map(& &1.facts)
    |> Enum.find(&(&1.fact_id == fact_id))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="flex items-center justify-between mb-3">
        <.link
          navigate={~p"/nutritionist/research"}
          class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4" /> {gettext("All research")}
        </.link>
        <.link
          navigate={~p"/nutritionist/research/notes"}
          class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment"
        >
          <.icon name="hero-bookmark" class="w-4 h-4" /> {gettext("My notes")}
        </.link>
      </div>

      <% visible = sorted_groups(@groups, @sort) %>

      <header class="mb-4">
        <h1 class="text-2xl font-semibold text-parchment">{@condition.name}</h1>
        <p class="text-sm text-parchment-dim mt-1">
          {ngettext(
            "%{count} publication with food-related facts.",
            "%{count} publications with food-related facts.",
            @publication_count
          )}
        </p>
      </header>

      <div
        :if={@groups != []}
        class="flex flex-wrap items-center gap-2 mb-6 pb-4 border-b border-ink-panel2"
      >
        <form id="research-sort" phx-change="set_sort" class="ml-auto flex items-center gap-1.5">
          <label for="sort" class="text-xs text-parchment-dim">{gettext("Sort")}</label>
          <select
            id="sort"
            name="sort"
            class="rounded-md border border-ink-panel2 bg-ink-panel2 text-parchment text-xs px-2 py-1 focus:outline-none focus:ring-1 focus:ring-basil/50"
          >
            <option :for={{key, label} <- sort_options()} value={key} selected={@sort == key}>
              {label}
            </option>
          </select>
        </form>
      </div>

      <p
        :if={@groups == [] and @free_publications == []}
        class="text-sm text-parchment-dim py-8 text-center"
      >
        {gettext("No digested research for this condition yet.")}
      </p>

      <%!-- Presentable publications — grouped by research type, with quotes. --%>
      <details :for={group <- visible} class="mb-8 group/bucket" open>
        <summary class="list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-parchment-dim hover:text-parchment">
          <.icon
            name="hero-chevron-right"
            class="w-3.5 h-3.5 transition-transform group-open/bucket:rotate-90"
          />
          {group.label}
          <span class="text-[10px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim normal-case tracking-normal">
            {length(group.publications)}
          </span>
        </summary>

        <div>
          <.publication_card
            :for={pub <- group.publications}
            pub={pub}
            presentable={true}
            saved_keys={@saved_keys}
            composing_study_id={@composing_study_id}
          />
        </div>
      </details>

      <%!-- Free claims — distilled facts from papers we may not reproduce. --%>
      <section :if={@free_publications != []} class="mb-8">
        <div class="mb-2 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-parchment-dim">
          {gettext("Free claims")}
          <span class="text-[10px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim normal-case tracking-normal">
            {length(@free_publications)}
          </span>
        </div>
        <p class="text-xs text-parchment-dim mb-3">
          {gettext(
            "Findings from publications we may not reproduce here — our wording only, with a link to the source."
          )}
        </p>

        <.publication_card
          :for={pub <- @free_publications}
          pub={pub}
          presentable={false}
          saved_keys={@saved_keys}
          composing_study_id={@composing_study_id}
        />
      </section>
    </div>
    """
  end

  # ── Publication card (shared by the presentable groups + the free-claims list) ─

  attr :pub, :map, required: true
  attr :presentable, :boolean, required: true
  attr :saved_keys, :any, required: true
  attr :composing_study_id, :any, required: true

  defp publication_card(assigns) do
    ~H"""
    <article class="mb-3 p-4 rounded-xl bg-ink-panel2 border border-ink-panel2">
      <a
        href={pubmed_url(@pub)}
        target="_blank"
        rel="noopener"
        class="text-parchment font-medium hover:text-basil hover:underline"
      >
        {@pub.title || gettext("PMID %{pmid}", pmid: @pub.pmid || "—")}
      </a>

      <p :if={authors_line(@pub.authors)} class="text-xs text-parchment-dim mt-1">
        {authors_line(@pub.authors)}
      </p>

      <div class="flex flex-wrap items-center gap-1.5 mt-2 text-[10px]">
        <span
          :if={@pub.medline?}
          class="px-2 py-0.5 rounded-full bg-basil/15 text-basil font-medium"
          title={gettext("Published in a MEDLINE-indexed journal — vetted and selectively indexed by the U.S. National Library of Medicine.")}
        >
          {gettext("MEDLINE")}
        </span>
        <span :if={@pub.journal} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
          {@pub.journal}
        </span>
        <span :if={@pub.publication_year} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
          {@pub.publication_year}
        </span>
        <span
          :if={not @presentable}
          class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim italic"
          title={gettext("The paper's licence does not permit reproducing its text here — read it at the source.")}
        >
          {gettext("full text not shown")}
        </span>
      </div>

      <ul class="mt-3 space-y-2">
        <li :for={fact <- @pub.facts} class="pl-3 border-l-2 border-ink text-xs">
          <div class="text-parchment">
            {fact.text}
            <span class={["ml-1", label_class(fact.label)]}>{label_text(fact.label)}</span>
            <span :if={fact.certainty} class="text-parchment-dim">· {certainty_text(fact.certainty)}</span>
          </div>

          <p :if={@presentable and is_binary(fact.quote)} class="text-parchment-dim/80 italic mt-0.5">
            “{fact.quote}”
          </p>

          <div class="flex items-center gap-3 mt-1">
            <a
              href={pubmed_url(@pub)}
              target="_blank"
              rel="noopener"
              class="text-basil hover:underline"
            >
              {gettext("source")}
            </a>
            <button
              :if={@pub.study_id}
              type="button"
              phx-click="toggle_save"
              phx-value-study_id={@pub.study_id}
              phx-value-claim_id={fact.fact_id}
              aria-pressed={saved?(@saved_keys, @pub.study_id, fact.fact_id)}
              class={[
                "inline-flex items-center gap-0.5 transition-colors",
                if(saved?(@saved_keys, @pub.study_id, fact.fact_id),
                  do: "text-basil",
                  else: "text-parchment-dim hover:text-parchment"
                )
              ]}
            >
              <.icon
                name={
                  if saved?(@saved_keys, @pub.study_id, fact.fact_id),
                    do: "hero-bookmark-solid",
                    else: "hero-bookmark"
                }
                class="w-3 h-3"
              />
              {if saved?(@saved_keys, @pub.study_id, fact.fact_id),
                do: gettext("Saved"),
                else: gettext("Save")}
            </button>
          </div>
        </li>
      </ul>

      <%!-- Write your own note against this paper (saved to "My notes"). --%>
      <button
        :if={@pub.study_id && @composing_study_id != @pub.study_id}
        type="button"
        phx-click="compose_note"
        phx-value-study_id={@pub.study_id}
        class="mt-3 inline-flex items-center gap-1 text-xs text-parchment-dim hover:text-parchment"
      >
        <.icon name="hero-plus" class="w-3 h-3" /> {gettext("Write your own note")}
      </button>

      <form :if={@composing_study_id == @pub.study_id} phx-submit="save_custom" class="mt-3">
        <input type="hidden" name="study_id" value={@pub.study_id} />
        <textarea
          name="body"
          rows="3"
          autofocus
          placeholder={gettext("Your note about this paper…")}
          class="w-full rounded-md border border-ink-panel2 bg-ink text-parchment text-xs px-2.5 py-2 focus:outline-none focus:ring-1 focus:ring-basil/50"
        ></textarea>
        <div class="flex items-center gap-2 mt-1.5">
          <button
            type="submit"
            class="px-2.5 py-1 rounded-md bg-basil/15 text-basil text-xs hover:bg-basil/25"
          >
            {gettext("Save note")}
          </button>
          <button
            type="button"
            phx-click="cancel_compose"
            class="text-xs text-parchment-dim hover:text-parchment"
          >
            {gettext("Cancel")}
          </button>
        </div>
      </form>
    </article>
    """
  end

  # ── View helpers ────────────────────────────────────────────────────────────

  defp saved?(saved_keys, study_id, fact_id),
    do: MapSet.member?(saved_keys, {study_id, fact_id})

  defp pubmed_url(%{pmid: pmid}) when is_binary(pmid) and pmid != "",
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp pubmed_url(_), do: "https://pubmed.ncbi.nlm.nih.gov/"

  defp authors_line(authors) when is_list(authors) and authors != [] do
    case authors do
      [a] -> a
      [a, b] -> "#{a}, #{b}"
      [a, b | _] -> "#{a}, #{b}, et al."
    end
  end

  defp authors_line(_), do: nil

  defp label_text("verified"), do: gettext("verified")
  defp label_text("contradicted"), do: gettext("contradicted")
  defp label_text(_unverified), do: gettext("unverified")

  defp label_class("verified"), do: "text-basil"
  defp label_class("contradicted"), do: "text-paprika"
  defp label_class(_unverified), do: "text-parchment-dim"

  defp certainty_text("high"), do: gettext("high certainty")
  defp certainty_text("moderate"), do: gettext("moderate certainty")
  defp certainty_text("low"), do: gettext("low certainty")
  defp certainty_text("very_low"), do: gettext("very low certainty")
  defp certainty_text(other), do: other
end
