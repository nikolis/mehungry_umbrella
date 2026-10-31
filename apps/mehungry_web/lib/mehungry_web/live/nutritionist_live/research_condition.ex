defmodule MehungryWeb.NutritionistLive.ResearchCondition do
  @moduledoc """
  Nutritionist **research results** for one condition
  (`/nutritionist/research/:condition_id`).

  Renders the condition's digested research grouped by research type
  (`Literature.grouped_research_for_condition/1`), strongest evidence first. Each
  research-type group is collapsible.

  A result card leads with publication metadata. When the paper has open-access
  full text, its primary content is the **section outline** — each section title
  deep-links into the in-app reader (`ResearchPaper`) scrolled to that section;
  abstract-only papers keep the PubMed title link only. The extracted claims are
  tucked behind a per-card **"Suggested notes (N)"** toggle (hidden on first
  paint); each one links **"Open in text"** to the reader at the claim's evidence
  paragraph (`#par-…`), falling back to PubMed when the paper has no full text.

  Read-only. Claim visibility hides claims an admin curated as `wrong`/`ignore`;
  everything else (incl. un-curated claims) is shown.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Health
  alias Mehungry.Literature
  alias Mehungry.Literature.JournalAuthority
  alias Mehungry.Professionals.ResearchNotes

  @hidden_positions ~w(wrong ignore)

  # Within-group ordering the nutritionist can pick. `:relevance` is the default
  # (journal authority → recency → sample size — the context's own order).
  @sorts [
    relevance: "Best match",
    newest: "Newest first",
    sample: "Largest sample",
    findings: "Most findings"
  ]

  # One-click filters, each a predicate over a paper's metadata (AND-combined).
  @filters [
    full_text: "Full text",
    medline: "MEDLINE-indexed",
    independent: "Independent funding"
  ]

  @impl true
  def mount(%{"condition_id" => condition_id}, _session, socket) do
    condition = Health.get_condition!(condition_id)
    groups = Literature.grouped_research_for_condition(condition.id)
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, condition.name)
     |> assign(:condition, condition)
     |> assign(:groups, groups)
     |> assign(:sort, :relevance)
     |> assign(:filters, MapSet.new())
     |> assign(:study_count, Enum.sum(Enum.map(groups, &length(&1.analyses))))
     |> assign(:saved_keys, ResearchNotes.saved_claim_keys(user.id, condition.id))
     |> assign(:composing_study_id, nil)}
  end

  @impl true
  def handle_event("set_sort", %{"sort" => sort}, socket) do
    {:noreply, assign(socket, :sort, sort_key_atom(sort))}
  end

  def handle_event("toggle_filter", %{"filter" => filter}, socket) do
    filter = filter_key_atom(filter)

    filters =
      if MapSet.member?(socket.assigns.filters, filter),
        do: MapSet.delete(socket.assigns.filters, filter),
        else: MapSet.put(socket.assigns.filters, filter)

    {:noreply, assign(socket, :filters, filters)}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, assign(socket, :filters, MapSet.new())}
  end

  # Save ⇄ unsave a suggested note (the per-claim bookmark toggle).
  def handle_event("toggle_save", %{"study_id" => study_id, "claim_id" => claim_id}, socket) do
    study_id = String.to_integer(study_id)
    user = socket.assigns.current_user
    key = {study_id, claim_id}

    socket =
      if MapSet.member?(socket.assigns.saved_keys, key) do
        {:ok, _} = ResearchNotes.delete_suggested(user.id, study_id, claim_id)
        assign(socket, :saved_keys, MapSet.delete(socket.assigns.saved_keys, key))
      else
        case find_claim(socket.assigns.groups, study_id, claim_id) do
          {_analysis, claim} ->
            attrs =
              ResearchNotes.suggested_attrs_from_claim(socket.assigns.condition.id, study_id, claim)

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
      {:noreply, socket |> put_flash(:error, "Write something first.") |> assign(:composing_study_id, nil)}
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
       |> put_flash(:info, "Note saved to your notes.")}
    end
  end

  defp sort_key_atom(s), do: Enum.find(Keyword.keys(@sorts), &(to_string(&1) == s)) || :relevance
  defp filter_key_atom(f), do: Enum.find(Keyword.keys(@filters), &(to_string(&1) == f))

  defp sort_options, do: @sorts
  defp filter_options, do: @filters

  # Apply the active filters + chosen sort to each group's papers, dropping any
  # group left empty. Operates on the already-loaded groups (no DB round-trip).
  defp visible_groups(groups, filters, sort) do
    groups
    |> Enum.map(fn group ->
      analyses =
        group.analyses
        |> Enum.filter(&matches_filters?(&1, filters))
        |> sort_analyses(sort)

      %{group | analyses: analyses}
    end)
    |> Enum.reject(&(&1.analyses == []))
  end

  defp matches_filters?(analysis, filters), do: Enum.all?(filters, &filter_match?(&1, analysis))

  defp filter_match?(:full_text, a), do: a.has_full_text
  defp filter_match?(:medline, a), do: JournalAuthority.medline_indexed?(a.study)
  defp filter_match?(:independent, a), do: a.funding_independence == "independent"
  defp filter_match?(_, _), do: true

  # Ascending sort_by: negate integer fields so larger sorts first; nils sort last.
  defp sort_analyses(analyses, :newest),
    do: Enum.sort_by(analyses, &(-(&1.publication_year || -99_999)))

  defp sort_analyses(analyses, :sample), do: Enum.sort_by(analyses, &(-(&1.sample_size || 0)))

  defp sort_analyses(analyses, :findings),
    do: Enum.sort_by(analyses, &(-length(visible_claims(&1))))

  defp sort_analyses(analyses, _relevance), do: Enum.sort_by(analyses, &relevance_key/1)

  # The default order: MEDLINE-indexed first, then most-recent, then largest sample.
  defp relevance_key(a),
    do: {JournalAuthority.rank(a.study), -(a.publication_year || -99_999), -(a.sample_size || 0)}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="flex items-center justify-between mb-3">
        <.link
          navigate={~p"/nutritionist/research"}
          class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment"
        >
          <.icon name="hero-arrow-left" class="w-4 h-4" /> All research
        </.link>
        <.link
          navigate={~p"/nutritionist/research/notes"}
          class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment"
        >
          <.icon name="hero-bookmark" class="w-4 h-4" /> My notes
        </.link>
      </div>

      <% visible = visible_groups(@groups, @filters, @sort) %>
      <% shown = Enum.sum(Enum.map(visible, &length(&1.analyses))) %>

      <header class="mb-4">
        <h1 class="text-2xl font-semibold text-parchment">{@condition.name}</h1>
        <p class="text-sm text-parchment-dim mt-1">
          <span :if={MapSet.size(@filters) == 0}>
            {@study_count} nutrition-relevant stud{if @study_count == 1, do: "y", else: "ies"},
            grouped by research type (strongest evidence first).
          </span>
          <span :if={MapSet.size(@filters) > 0}>
            Showing {shown} of {@study_count} studies.
          </span>
        </p>
      </header>

      <%!-- Filter chips + sort — narrow and reorder by the metadata we extract. --%>
      <div
        :if={@groups != []}
        class="flex flex-wrap items-center gap-2 mb-6 pb-4 border-b border-ink-panel2"
      >
        <button
          :for={{key, label} <- filter_options()}
          type="button"
          phx-click="toggle_filter"
          phx-value-filter={key}
          aria-pressed={MapSet.member?(@filters, key)}
          class={[
            "inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs border transition-colors",
            if(MapSet.member?(@filters, key),
              do: "bg-basil/15 border-basil/40 text-basil",
              else: "bg-ink-panel2 border-ink-panel2 text-parchment-dim hover:text-parchment"
            )
          ]}
        >
          <.icon :if={MapSet.member?(@filters, key)} name="hero-check" class="w-3 h-3" />
          {label}
        </button>

        <button
          :if={MapSet.size(@filters) > 0}
          type="button"
          phx-click="clear_filters"
          class="text-xs text-parchment-dim hover:text-parchment underline"
        >
          Clear
        </button>

        <form id="research-sort" phx-change="set_sort" class="ml-auto flex items-center gap-1.5">
          <label for="sort" class="text-xs text-parchment-dim">Sort</label>
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

      <p :if={@groups == []} class="text-sm text-parchment-dim py-8 text-center">
        No digested research for this condition yet.
      </p>

      <p
        :if={@groups != [] and visible == []}
        class="text-sm text-parchment-dim py-8 text-center"
      >
        No studies match these filters.
        <button type="button" phx-click="clear_filters" class="text-basil hover:underline">
          Clear filters
        </button>
      </p>

      <details :for={group <- visible} class="mb-8 group/bucket" open>
        <summary class="list-none [&::-webkit-details-marker]:hidden cursor-pointer select-none mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-wide text-parchment-dim hover:text-parchment">
          <.icon
            name="hero-chevron-right"
            class="w-3.5 h-3.5 transition-transform group-open/bucket:rotate-90"
          />
          {group.label}
          <span class="text-[10px] px-2 py-0.5 rounded-full bg-ink-panel2 text-parchment-dim normal-case tracking-normal">
            {length(group.analyses)}
          </span>
        </summary>

        <div>
          <article
            :for={analysis <- group.analyses}
            class="mb-3 p-4 rounded-xl bg-ink-panel2 border border-ink-panel2"
          >
            <a
              href={pubmed_url(analysis)}
              target="_blank"
              rel="noopener"
              class="text-parchment font-medium hover:text-basil hover:underline"
            >
              {analysis.paper_title || (analysis.study && analysis.study.title) || "Untitled"}
            </a>

          <p :if={authors_line(analysis)} class="text-xs text-parchment-dim mt-1">
            {authors_line(analysis)}
          </p>

          <div class="flex flex-wrap items-center gap-1.5 mt-2 text-[10px]">
            <span
              :if={authority_label(analysis)}
              class="px-2 py-0.5 rounded-full bg-basil/15 text-basil font-medium"
              title="Published in a MEDLINE-indexed journal — vetted and selectively indexed by the U.S. National Library of Medicine."
            >
              {authority_label(analysis)}
            </span>
            <span :if={journal(analysis)} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
              {journal(analysis)}
            </span>
            <span :if={analysis.publication_year} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
              {analysis.publication_year}
            </span>
            <span :if={analysis.sample_size} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
              n = {analysis.sample_size}
            </span>
            <span
              :if={analysis.funding_independence in ["independent", "conflicted"]}
              class={[
                "px-2 py-0.5 rounded-full bg-ink",
                analysis.funding_independence == "independent" && "text-basil",
                analysis.funding_independence == "conflicted" && "text-paprika-soft"
              ]}
            >
              {funding_label(analysis.funding_independence)}
            </span>
            <span
              :if={analysis.source_type && analysis.source_type != "open_access"}
              class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim italic"
              title="Findings extracted from the abstract only (no open-access full text)"
            >
              abstract only
            </span>
          </div>

          <%!-- Full-text papers lead with their section outline: the paper's own
                numbered table of contents, 2.x nested under a collapsible 2.
                Collapsed by default so a long paper doesn't flood the card. --%>
            <details :if={analysis.has_full_text} class="mt-3 group/toc">
              <summary class="list-none [&::-webkit-details-marker]:hidden inline-flex items-baseline gap-1.5 cursor-pointer select-none text-xs font-medium text-basil hover:underline">
                <.icon
                  name="hero-chevron-right"
                  class="w-3 h-3 self-center transition-transform group-open/toc:rotate-90"
                />
                Read full text
                <span class="font-normal text-parchment-dim">
                  · {length(analysis.outline)} sections
                </span>
              </summary>

              <ol class="mt-2 space-y-px">
                <li :for={node <- outline_tree(analysis.outline)}>
                  <.link
                    :if={node.children == []}
                    navigate={reader_url(@condition.id, analysis.study_id, node.id)}
                    class="group/row flex items-baseline gap-2.5 rounded-md px-1.5 py-1 hover:bg-ink"
                  >
                    <span class="w-7 shrink-0 text-right tabular-nums text-xs text-parchment-dim">
                      {node.number}
                    </span>
                    <span class="text-sm text-parchment group-hover/row:text-basil">
                      {node.title}
                    </span>
                  </.link>

                  <details :if={node.children != []} class="group/sec">
                    <summary class="list-none [&::-webkit-details-marker]:hidden flex items-baseline gap-2.5 rounded-md px-1.5 py-1 cursor-pointer select-none hover:bg-ink">
                      <span class="w-7 shrink-0 text-right tabular-nums text-xs font-semibold text-basil">
                        {node.number}
                      </span>
                      <span class="text-sm text-parchment">{group_title(node)}</span>
                      <span class="ml-auto inline-flex items-center gap-1 text-[10px] text-parchment-dim">
                        {length(node.children)}
                        <.icon
                          name="hero-chevron-right"
                          class="w-3 h-3 transition-transform group-open/sec:rotate-90"
                        />
                      </span>
                    </summary>

                    <ul class="ml-[0.95rem] border-l border-ink-panel2 pl-2.5 py-0.5 space-y-px">
                      <li :for={child <- node.children}>
                        <.link
                          navigate={reader_url(@condition.id, analysis.study_id, child.id)}
                          class="group/row flex items-baseline gap-2.5 rounded-md px-1.5 py-1 hover:bg-ink"
                        >
                          <span class="w-8 shrink-0 text-right tabular-nums text-[11px] text-parchment-dim">
                            {child.number}
                          </span>
                          <span class="text-sm text-parchment-dim group-hover/row:text-basil">
                            {child.title}
                          </span>
                        </.link>
                      </li>
                    </ul>
                  </details>
                </li>
              </ol>
            </details>

            <%!-- Extracted findings are collapsed until the nutritionist asks. --%>
            <details :if={visible_claims(analysis) != []} class="mt-3 group/claims">
              <summary class="list-none [&::-webkit-details-marker]:hidden inline-flex items-center gap-1 cursor-pointer select-none text-xs text-parchment-dim hover:text-parchment">
                <.icon
                  name="hero-chevron-right"
                  class="w-3 h-3 transition-transform group-open/claims:rotate-90"
                />
                <span class="group-open/claims:hidden">{show_findings_label(analysis)}</span>
                <span class="hidden group-open/claims:inline">Hide suggested notes</span>
              </summary>

              <ul class="mt-2 space-y-2">
                <li
                  :for={claim <- visible_claims(analysis)}
                  class="pl-3 border-l-2 border-ink text-xs"
                >
                  <div
                    :if={disease_state(claim)}
                    class="text-[10px] inline-block px-2 py-0.5 rounded-full bg-paprika/20 text-paprika-soft mb-0.5"
                  >
                    disease state: {disease_state(claim)}
                  </div>
                  <div class="text-parchment">
                    <span class="font-medium">{endpoint(claim, "subject")}</span>
                    <span class="text-parchment-dim"> — {claim["predicate"]} — </span>
                    <span class="font-medium">{endpoint(claim, "object")}</span>
                    <span class={["ml-1", polarity_class(claim["polarity"])]}>
                      {claim["polarity"]}{certainty_suffix(claim)}
                    </span>
                  </div>
                  <p :if={first_quote(claim)} class="text-parchment-dim/80 italic mt-0.5">
                    “{first_quote(claim)}”
                  </p>
                  <% {kind, target} = claim_target(@condition.id, analysis, claim) %>
                  <% saved = saved?(@saved_keys, analysis.study_id, claim["claim_id"]) %>
                  <div class="flex items-center gap-3 mt-1">
                    <.link
                      :if={kind == :reader}
                      navigate={target}
                      class="inline-flex items-center gap-0.5 text-basil hover:underline"
                    >
                      <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" /> Open in text
                    </.link>
                    <a
                      :if={kind == :pubmed}
                      href={target}
                      target="_blank"
                      rel="noopener"
                      class="text-basil hover:underline"
                    >
                      source
                    </a>
                    <button
                      type="button"
                      phx-click="toggle_save"
                      phx-value-study_id={analysis.study_id}
                      phx-value-claim_id={claim["claim_id"]}
                      aria-pressed={saved}
                      class={[
                        "inline-flex items-center gap-0.5 transition-colors",
                        if(saved, do: "text-basil", else: "text-parchment-dim hover:text-parchment")
                      ]}
                    >
                      <.icon
                        name={if saved, do: "hero-bookmark-solid", else: "hero-bookmark"}
                        class="w-3 h-3"
                      />
                      {if saved, do: "Saved", else: "Save"}
                    </button>
                  </div>
                </li>
              </ul>
            </details>

            <p
              :if={not analysis.has_full_text and visible_claims(analysis) == []}
              class="mt-3 text-xs text-parchment-dim italic"
            >
              No highlighted findings for this paper.
            </p>

            <%!-- Write your own note against this paper (saved to "My notes"). --%>
            <button
              :if={@composing_study_id != analysis.study_id}
              type="button"
              phx-click="compose_note"
              phx-value-study_id={analysis.study_id}
              class="mt-3 inline-flex items-center gap-1 text-xs text-parchment-dim hover:text-parchment"
            >
              <.icon name="hero-plus" class="w-3 h-3" /> Write your own note
            </button>

            <form
              :if={@composing_study_id == analysis.study_id}
              phx-submit="save_custom"
              class="mt-3"
            >
              <input type="hidden" name="study_id" value={analysis.study_id} />
              <textarea
                name="body"
                rows="3"
                autofocus
                placeholder="Your note about this paper…"
                class="w-full rounded-md border border-ink-panel2 bg-ink text-parchment text-xs px-2.5 py-2 focus:outline-none focus:ring-1 focus:ring-basil/50"
              ></textarea>
              <div class="flex items-center gap-2 mt-1.5">
                <button
                  type="submit"
                  class="px-2.5 py-1 rounded-md bg-basil/15 text-basil text-xs hover:bg-basil/25"
                >
                  Save note
                </button>
                <button
                  type="button"
                  phx-click="cancel_compose"
                  class="text-xs text-parchment-dim hover:text-parchment"
                >
                  Cancel
                </button>
              </div>
            </form>
          </article>
        </div>
      </details>
    </div>
    """
  end

  # Deep-link to the in-app reader, anchored to a section.
  defp reader_url(condition_id, study_id, section_id) do
    ~p"/nutritionist/research/#{condition_id}/paper/#{study_id}" <> "#sec-#{section_id}"
  end

  # ── Section outline → the paper's numbered table of contents ────────────────
  # The section titles carry the authors' own numbering ("2.1. Systemic …").
  # Build a two-level tree: each `x.y` nests under its top-level number `x`, so the
  # card can render a collapsing hierarchy instead of a flat wall of links.

  # "2.1. Systemic Inflammation…" → {[2, 1], "Systemic Inflammation…"};
  # an unnumbered heading → {nil, title}.
  defp parse_section_number(title) when is_binary(title) do
    case Regex.run(~r/^\s*(\d+(?:\.\d+)*)\.?\s+(.*\S)\s*$/, title) do
      [_, number, rest] ->
        {number |> String.split(".") |> Enum.map(&String.to_integer/1), rest}

      _ ->
        {nil, String.trim(title)}
    end
  end

  defp parse_section_number(_), do: {nil, ""}

  # Flat `[%{"id","title"}]` → ordered nodes. A node is either a leaf (link) or a
  # group with `children`. Document order is preserved.
  defp outline_tree(outline) do
    Enum.reduce(outline, [], fn %{"id" => id, "title" => title}, nodes ->
      case parse_section_number(title) do
        {nil, label} ->
          nodes ++ [%{key: {:unnumbered, id}, number: nil, title: label, id: id, children: []}]

        {[top], label} ->
          # A real top-level section (e.g. "1. Introduction") — carries its own link.
          upsert_group(nodes, top, &%{&1 | title: label, id: id})

        {[top | _] = segs, label} ->
          child = %{number: Enum.join(segs, "."), title: label, id: id}
          upsert_group(nodes, top, &%{&1 | children: &1.children ++ [child]})
      end
    end)
  end

  defp upsert_group(nodes, top, fun) do
    key = {:numbered, top}

    if Enum.any?(nodes, &(&1.key == key)) do
      Enum.map(nodes, fn node -> if node.key == key, do: fun.(node), else: node end)
    else
      nodes ++ [fun.(%{key: key, number: Integer.to_string(top), title: nil, id: nil, children: []})]
    end
  end

  # A group's label: its own section title when the paper has one (e.g. "Methods"),
  # else the numeric range it spans (e.g. "2.1–2.3") — honest when there's no parent
  # heading in the source.
  defp group_title(%{title: title}) when is_binary(title), do: title

  defp group_title(%{children: children}) do
    case Enum.map(children, & &1.number) do
      [only] -> only
      nums -> "#{List.first(nums)}–#{List.last(nums)}"
    end
  end

  # ── Claim display (mirrors the claim JSON shape stored by StudyAnalyses) ─────

  defp visible_claims(%{claims: claims}) when is_list(claims),
    do: Enum.reject(claims, &(&1["position"] in @hidden_positions))

  defp visible_claims(_), do: []

  defp show_findings_label(analysis), do: "Suggested notes (#{length(visible_claims(analysis))})"

  # "Open in text": deep-link to the reader at the claim's first evidence
  # paragraph when the paper has full text; else fall back to PubMed.
  defp claim_target(condition_id, analysis, claim) do
    case {analysis.has_full_text, first_paragraph_id(claim)} do
      {true, pid} when is_binary(pid) ->
        {:reader, reader_paragraph_url(condition_id, analysis.study_id, pid)}

      _ ->
        {:pubmed, pubmed_url(analysis)}
    end
  end

  defp first_paragraph_id(%{"evidence" => [%{"paragraph_id" => pid} | _]}) when is_binary(pid),
    do: pid

  defp first_paragraph_id(_), do: nil

  defp reader_paragraph_url(condition_id, study_id, paragraph_id) do
    ~p"/nutritionist/research/#{condition_id}/paper/#{study_id}" <> "#par-#{paragraph_id}"
  end

  # ── Suggested-note save state + provenance snapshot ─────────────────────────

  defp saved?(saved_keys, study_id, claim_id),
    do: MapSet.member?(saved_keys, {study_id, claim_id})

  # Locate a claim (by id) within the already-loaded groups so a Save can snapshot
  # its data server-side — never trusting a client-submitted body/quote.
  defp find_claim(groups, study_id, claim_id) do
    Enum.find_value(groups, fn group ->
      Enum.find_value(group.analyses, fn analysis ->
        if analysis.study_id == study_id do
          case Enum.find(visible_claims(analysis), &(&1["claim_id"] == claim_id)) do
            nil -> nil
            claim -> {analysis, claim}
          end
        end
      end)
    end)
  end


  defp endpoint(claim, side),
    do: claim["#{side}_label"] || claim["#{side}_name"] || claim["#{side}_text"]

  defp first_quote(%{"evidence" => [%{"quoted_text" => q} | _]}) when is_binary(q), do: q
  defp first_quote(_), do: nil

  defp disease_state(claim) do
    (claim["qualifiers"] || [])
    |> Enum.find_value(fn q ->
      if q["qualifier_type"] == "disease_state", do: q["value_text"]
    end)
  end

  defp certainty_suffix(%{"certainty" => "hedged"}), do: " · hedged"
  defp certainty_suffix(_), do: ""

  defp polarity_class("positive"), do: "text-basil"
  defp polarity_class("negative"), do: "text-paprika"
  defp polarity_class(_), do: "text-parchment-dim"

  # ── Publication metadata ────────────────────────────────────────────────────

  defp pubmed_url(%{study: %{pmid: pmid}}) when is_integer(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp pubmed_url(_), do: "https://pubmed.ncbi.nlm.nih.gov/"

  defp journal(%{study: %{journal: j}}) when is_binary(j) and j != "", do: j
  defp journal(_), do: nil

  defp authority_label(%{study: study}), do: JournalAuthority.label(study)
  defp authority_label(_), do: nil

  defp authors_line(%{study: %{authors: authors}}) when is_list(authors) and authors != [] do
    case authors do
      [a] -> a
      [a, b] -> "#{a}, #{b}"
      [a, b | _] -> "#{a}, #{b}, et al."
    end
  end

  defp authors_line(_), do: nil

  defp funding_label("independent"), do: "independent funding"
  defp funding_label("conflicted"), do: "conflicted funding"
  defp funding_label(other), do: other
end
