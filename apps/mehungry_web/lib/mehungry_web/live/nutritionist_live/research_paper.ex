defmodule MehungryWeb.NutritionistLive.ResearchPaper do
  @moduledoc """
  The in-app **full-text reader** for one digested study
  (`/nutritionist/research/:condition_id/paper/:study_id`).

  Renders the paper's structured `sections` (the outline the `mehungry_extractor`
  `/analyze` response carries for open-access papers, stored on `StudyFullText`)
  with per-section (`#sec-<section_id>`) and per-paragraph (`#par-<paragraph_id>`)
  anchors, so a results-page section link scrolls straight to the deep-linked
  part. Each paragraph's extracted-claim evidence spans are highlighted inline
  (`<mark>`, tinted by polarity). The browser handles the `#sec-…`/`#par-…`
  fragment scroll on load.

  Offered only for papers that have a stored full-text outline; a study without
  one redirects back to the condition's results page.

  A **floating, independent notes widget** (bottom-right, collapsible) lets the
  nutritionist **Save** the paper's suggested notes and **write their own**: the
  "write your own note" button enters a selection mode (the article gets a text
  cursor via `data-note-mode` + the `NoteSelection` JS hook), the highlighted
  passage becomes the note's sub-text (`quoted_text`), and the nutritionist types
  the title (`body`). Persisted via `Mehungry.Professionals.ResearchNotes`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Health
  alias Mehungry.Literature
  alias Mehungry.Literature.JournalAuthority
  alias Mehungry.Professionals.ResearchNotes

  @hidden_positions ~w(wrong ignore)
  @max_passage_length 2000

  @impl true
  def mount(%{"condition_id" => condition_id, "study_id" => study_id}, _session, socket) do
    condition = Health.get_condition!(condition_id)

    case Literature.full_text_for_reader(study_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "No full text available for this paper.")
         |> push_navigate(to: ~p"/nutritionist/research/#{condition.id}")}

      data ->
        {:ok,
         socket
         |> assign(:page_title, data.study && data.study.title)
         |> assign(:condition, condition)
         |> assign(:study, data.study)
         |> assign(:analysis, data.analysis)
         |> assign(:sections, data.sections)
         |> assign(:spans_by_paragraph, data.spans_by_paragraph)
         |> assign(:claims, visible_claims(data.analysis))
         |> assign(:note_mode, false)
         |> assign(:selection, nil)
         |> assign(:panel_collapsed, false)
         |> refresh_notes()}
    end
  end

  # Reload the nutritionist's save-state + their existing notes for this paper
  # after any note mutation — the single source of truth for the widget.
  defp refresh_notes(socket) do
    %{current_user: user, study: study, condition: condition, sections: sections} = socket.assigns
    my_notes = ResearchNotes.list_for_user_and_study(user.id, study.id)

    socket
    |> assign(:saved_keys, ResearchNotes.saved_claim_keys(user.id, condition.id))
    |> assign(:my_notes, my_notes)
    |> assign(:note_spans_by_paragraph, note_spans_by_paragraph(my_notes, sections))
  end

  @impl true
  # Save ⇄ unsave a suggested note from the reader's notes widget.
  def handle_event("toggle_save", %{"claim_id" => claim_id}, socket) do
    %{study: study, condition: condition, current_user: user} = socket.assigns

    if MapSet.member?(socket.assigns.saved_keys, {study.id, claim_id}) do
      {:ok, _} = ResearchNotes.delete_suggested(user.id, study.id, claim_id)
    else
      case Enum.find(socket.assigns.claims, &(&1["claim_id"] == claim_id)) do
        nil ->
          :noop

        claim ->
          attrs = ResearchNotes.suggested_attrs_from_claim(condition.id, study.id, claim)
          {:ok, _} = ResearchNotes.save_suggested(user.id, attrs)
      end
    end

    {:noreply, refresh_notes(socket)}
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    {:ok, _} = ResearchNotes.delete_note(socket.assigns.current_user.id, String.to_integer(id))
    {:noreply, socket |> refresh_notes() |> put_flash(:info, "Note removed.")}
  end

  # Enter "mark a passage" mode: the article gets a selection cursor and the next
  # text selection is captured as the note's sub-text (via the NoteSelection hook).
  def handle_event("start_note", _params, socket) do
    {:noreply, socket |> assign(:note_mode, true) |> assign(:selection, nil)}
  end

  def handle_event("cancel_note", _params, socket) do
    {:noreply, socket |> assign(:note_mode, false) |> assign(:selection, nil)}
  end

  # A passage was highlighted in the article while in note mode.
  def handle_event("select_passage", %{"text" => text} = params, socket) do
    if socket.assigns.note_mode and is_binary(text) and String.trim(text) != "" do
      selection = %{
        text: text |> String.trim() |> String.slice(0, @max_passage_length),
        paragraph_id: params["paragraph_id"],
        section_id: params["section_id"]
      }

      {:noreply, assign(socket, :selection, selection)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("save_custom", %{"title" => title}, socket) do
    %{study: study, condition: condition, current_user: user, selection: selection} = socket.assigns
    title = String.trim(title)

    cond do
      title == "" ->
        {:noreply, put_flash(socket, :error, "Give your note a title first.")}

      true ->
        {:ok, _} =
          ResearchNotes.create_custom(user.id, %{
            condition_id: condition.id,
            study_id: study.id,
            body: title,
            quoted_text: selection && selection.text,
            section_id: selection && selection.section_id,
            paragraph_id: selection && selection.paragraph_id
          })

        {:noreply,
         socket
         |> assign(:note_mode, false)
         |> assign(:selection, nil)
         |> refresh_notes()
         |> put_flash(:info, "Note saved to your notes.")}
    end
  end

  def handle_event("toggle_panel", _params, socket) do
    {:noreply, assign(socket, :panel_collapsed, !socket.assigns.panel_collapsed)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.link
        navigate={~p"/nutritionist/research/#{@condition.id}"}
        class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment mb-3"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" /> {@condition.name}
      </.link>

      <header class="mb-6 pb-4 border-b border-ink-panel2">
        <h1 class="text-2xl font-semibold text-parchment">{title(@study)}</h1>

        <p :if={authors_line(@study)} class="text-sm text-parchment-dim mt-1">
          {authors_line(@study)}
        </p>

        <div class="flex flex-wrap items-center gap-1.5 mt-2 text-[10px]">
          <span
            :if={JournalAuthority.label(@study)}
            class="px-2 py-0.5 rounded-full bg-basil/15 text-basil font-medium"
          >
            {JournalAuthority.label(@study)}
          </span>
          <span :if={journal(@study)} class="px-2 py-0.5 rounded-full bg-ink text-parchment-dim">
            {journal(@study)}
          </span>
          <a
            href={pubmed_url(@study)}
            target="_blank"
            rel="noopener"
            class="px-2 py-0.5 rounded-full bg-ink text-basil hover:underline"
          >
            View on PubMed
          </a>
        </div>
      </header>

      <article
        id="reader-article"
        phx-hook="NoteSelection"
        data-note-mode={to_string(@note_mode)}
        class={[
          "space-y-6 transition-all",
          @note_mode && "cursor-text [&_*]:cursor-text ring-2 ring-basil/30 rounded-lg -mx-2 px-2 py-1"
        ]}
      >
        <section
          :for={section <- @sections}
          id={"sec-" <> section["section_id"]}
          class={["scroll-mt-20", subsection_indent(section)]}
        >
          <h2 class={[
            "flex items-baseline gap-2 mb-2 scroll-mt-20",
            if(subsection?(section),
              do: "text-sm font-medium text-parchment-dim",
              else: "text-base font-semibold text-parchment"
            )
          ]}>
            <span
              :if={section_number(section)}
              class="shrink-0 tabular-nums text-basil"
            >
              {section_number(section)}
            </span>
            <span>{section_label(section)}</span>
          </h2>

          <p
            :for={paragraph <- section["paragraphs"] || []}
            id={"par-" <> paragraph["paragraph_id"]}
            class="text-sm text-parchment-dim leading-relaxed mb-3 scroll-mt-20"
          >
            <%= for segment <- segments(paragraph, @spans_by_paragraph, @note_spans_by_paragraph) do %>
              <mark
                :if={elem(segment, 0) == :mark}
                class={["rounded px-0.5 text-parchment", elem(segment, 2)]}
              >{elem(segment, 1)}</mark><span :if={elem(segment, 0) == :text}>{elem(segment, 1)}</span>
            <% end %>
          </p>
        </section>
      </article>

      <%!-- Floating, independent notes widget: save the paper's suggested notes
            and write your own against a highlighted passage. --%>
      <div class="fixed bottom-4 right-4 z-40 w-80 max-w-[calc(100vw-2rem)]">
        <button
          :if={@panel_collapsed}
          type="button"
          phx-click="toggle_panel"
          class="ml-auto flex items-center gap-1.5 px-3 py-2 rounded-full bg-ink-panel2 border border-ink-panel2 text-sm text-parchment shadow-lg hover:border-basil/40"
        >
          <.icon name="hero-bookmark" class="w-4 h-4" /> Notes
          <span :if={@claims != []} class="text-xs text-parchment-dim">({length(@claims)})</span>
        </button>

        <div
          :if={not @panel_collapsed}
          class="rounded-xl bg-ink-panel border border-ink-panel2 shadow-xl overflow-hidden flex flex-col max-h-[70vh]"
        >
          <div class="flex items-center justify-between px-3 py-2 border-b border-ink-panel2">
            <span class="text-xs font-semibold uppercase tracking-wide text-parchment-dim">Notes</span>
            <div class="flex items-center gap-2.5">
              <.link
                navigate={~p"/nutritionist/research/notes"}
                class="text-parchment-dim hover:text-parchment"
                title="My notes"
              >
                <.icon name="hero-bookmark" class="w-4 h-4" />
              </.link>
              <button
                type="button"
                phx-click="toggle_panel"
                class="text-parchment-dim hover:text-parchment"
                aria-label="Collapse notes"
              >
                <.icon name="hero-chevron-down" class="w-4 h-4" />
              </button>
            </div>
          </div>

          <div class="overflow-auto p-3 space-y-3">
            <%!-- Write your own note (select a passage → sub-text, type the title). --%>
            <button
              :if={not @note_mode}
              type="button"
              phx-click="start_note"
              class="inline-flex items-center gap-1 text-xs text-basil hover:underline"
            >
              <.icon name="hero-pencil-square" class="w-3.5 h-3.5" /> Write your own note
            </button>

            <div :if={@note_mode} class="rounded-lg border border-basil/40 bg-ink p-2.5">
              <p :if={is_nil(@selection)} class="text-xs text-parchment-dim flex items-start gap-1">
                <.icon name="hero-cursor-arrow-rays" class="w-3.5 h-3.5 shrink-0 mt-0.5" />
                Select a passage in the text to quote it, then add a title.
              </p>
              <p
                :if={@selection}
                class="text-xs text-parchment-dim/80 italic border-l-2 border-basil/40 pl-2"
              >
                “{@selection.text}”
              </p>

              <form phx-submit="save_custom" class="mt-2">
                <input
                  type="text"
                  name="title"
                  autocomplete="off"
                  placeholder="Note title…"
                  class="w-full rounded-md border border-ink-panel2 bg-ink-panel text-parchment text-xs px-2.5 py-1.5 focus:outline-none focus:ring-1 focus:ring-basil/50"
                />
                <div class="flex items-center gap-2 mt-1.5">
                  <button
                    type="submit"
                    class="px-2.5 py-1 rounded-md bg-basil/15 text-basil text-xs hover:bg-basil/25"
                  >
                    Save note
                  </button>
                  <button
                    type="button"
                    phx-click="cancel_note"
                    class="text-xs text-parchment-dim hover:text-parchment"
                  >
                    Cancel
                  </button>
                </div>
              </form>
            </div>

            <%!-- The nutritionist's existing notes for this paper. --%>
            <div :if={@my_notes != []} class="border-t border-ink-panel2 pt-3">
              <p class="text-xs font-medium text-parchment-dim mb-2">
                Your notes ({length(@my_notes)})
              </p>
              <ul class="space-y-2.5">
                <li
                  :for={note <- @my_notes}
                  class="text-xs border-l-2 border-basil/40 pl-2 flex items-start justify-between gap-2"
                >
                  <div>
                    <a
                      :if={note_anchor(note)}
                      href={note_anchor(note)}
                      class="text-parchment hover:text-accent-400 hover:underline"
                    >
                      {note.body}
                    </a>
                    <p :if={is_nil(note_anchor(note))} class="text-parchment">{note.body}</p>
                    <p :if={note.quoted_text} class="text-parchment-dim/80 italic mt-0.5">
                      “{note.quoted_text}”
                    </p>
                  </div>
                  <button
                    type="button"
                    phx-click="delete_note"
                    phx-value-id={note.id}
                    data-confirm="Remove this note?"
                    class="shrink-0 text-parchment-dim hover:text-paprika"
                    aria-label="Remove note"
                  >
                    <.icon name="hero-trash" class="w-3.5 h-3.5" />
                  </button>
                </li>
              </ul>
            </div>

            <%!-- Suggested notes for this paper — a closed list, expand on demand. --%>
            <details :if={@claims != []} class="border-t border-ink-panel2 pt-3 group/suggested">
              <summary class="list-none [&::-webkit-details-marker]:hidden inline-flex items-center gap-1 cursor-pointer select-none text-xs font-medium text-parchment-dim hover:text-parchment">
                <.icon
                  name="hero-chevron-right"
                  class="w-3 h-3 transition-transform group-open/suggested:rotate-90"
                />
                Suggested notes ({length(@claims)})
              </summary>
              <ul class="space-y-2.5 mt-2">
                <li :for={claim <- @claims} class="text-xs">
                  <a
                    :if={claim_anchor(claim)}
                    href={claim_anchor(claim)}
                    class="block text-parchment hover:text-basil"
                  >
                    <.claim_prose claim={claim} />
                  </a>
                  <div :if={is_nil(claim_anchor(claim))} class="text-parchment">
                    <.claim_prose claim={claim} />
                  </div>
                  <% saved = saved?(@saved_keys, @study.id, claim["claim_id"]) %>
                  <button
                    type="button"
                    phx-click="toggle_save"
                    phx-value-claim_id={claim["claim_id"]}
                    aria-pressed={saved}
                    class={[
                      "inline-flex items-center gap-0.5 mt-0.5",
                      if(saved, do: "text-basil", else: "text-parchment-dim hover:text-parchment")
                    ]}
                  >
                    <.icon
                      name={if saved, do: "hero-bookmark-solid", else: "hero-bookmark"}
                      class="w-3 h-3"
                    />
                    {if saved, do: "Saved", else: "Save"}
                  </button>
                </li>
              </ul>
            </details>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp claim_prose(assigns) do
    ~H"""
    <span class="font-medium">{endpoint(@claim, "subject")}</span>
    <span class="text-parchment-dim"> — {@claim["predicate"]} — </span>
    <span class="font-medium">{endpoint(@claim, "object")}</span>
    """
  end

  # ── Claim-span highlighting ─────────────────────────────────────────────────

  # A paragraph's text split into an ordered list of segments:
  #   {:text, string} | {:mark, string, css_class}
  # from the paragraph-relative claim spans (polarity-tinted) unioned with the
  # nutritionist's own note spans (accent-tinted). Overlaps merged, out-of-range
  # dropped. Offsets are codepoint-based; we slice the text directly.
  defp segments(paragraph, spans_by_paragraph, note_spans_by_paragraph) do
    text = paragraph["text"] || ""
    len = String.length(text)
    pid = paragraph["paragraph_id"]

    claim_spans =
      spans_by_paragraph
      |> Map.get(pid, [])
      |> Enum.map(&{clamp(&1.start, len), clamp(&1.end, len), mark_class(&1.polarity)})

    note_spans =
      note_spans_by_paragraph
      |> Map.get(pid, [])
      |> Enum.map(fn {s, e} -> {clamp(s, len), clamp(e, len), note_mark_class()} end)

    (claim_spans ++ note_spans)
    |> Enum.reject(fn {s, e, _} -> e <= s end)
    |> merge_spans()
    |> then(&build_segments(text, &1, 0, len, []))
  end

  defp clamp(n, len) when is_integer(n), do: n |> max(0) |> min(len)
  defp clamp(_, _), do: 0

  # Coalesce overlapping/adjacent spans (keep the earlier span's class).
  defp merge_spans(spans) do
    spans
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce([], fn
      span, [] ->
        [span]

      {s, e, _class}, [{ps, pe, pclass} | rest] when s <= pe ->
        [{ps, max(pe, e), pclass} | rest]

      span, acc ->
        [span | acc]
    end)
    |> Enum.reverse()
  end

  defp build_segments(text, [], cursor, len, acc) do
    acc = if cursor < len, do: [{:text, slice(text, cursor, len)} | acc], else: acc
    Enum.reverse(acc)
  end

  defp build_segments(text, [{s, e, class} | rest], cursor, len, acc) do
    acc = if s > cursor, do: [{:text, slice(text, cursor, s)} | acc], else: acc
    acc = [{:mark, slice(text, s, e), class} | acc]
    build_segments(text, rest, e, len, acc)
  end

  defp slice(text, start, stop), do: String.slice(text, start, stop - start)

  defp mark_class("negative"), do: "bg-paprika/30"
  defp mark_class(_), do: "bg-basil/30"

  # The nutritionist's own note highlights — a distinct accent tint so they read
  # apart from the polarity-coloured claim spans.
  defp note_mark_class, do: "bg-accent-400/30"

  # paragraph_id => [{start, end}] codepoint spans for the nutritionist's custom
  # notes that marked a passage of this paper, by re-locating each stored quote in
  # its paragraph (whitespace-tolerant — the quote was whitespace-collapsed at save
  # time, the paragraph text keeps its original spacing).
  defp note_spans_by_paragraph(notes, sections) do
    texts = paragraph_texts(sections)

    notes
    |> Enum.filter(&(&1.kind == "custom" and &1.paragraph_id && &1.quoted_text))
    |> Enum.reduce(%{}, fn note, acc ->
      with text when is_binary(text) <- Map.get(texts, note.paragraph_id),
           {s, e} <- locate(text, note.quoted_text) do
        Map.update(acc, note.paragraph_id, [{s, e}], &[{s, e} | &1])
      else
        _ -> acc
      end
    end)
  end

  defp paragraph_texts(sections) do
    for section <- sections, p <- section["paragraphs"] || [], into: %{} do
      {p["paragraph_id"], p["text"] || ""}
    end
  end

  # Codepoint {start, end} of `quote` within `text`, matching across any run of
  # whitespace; nil when absent. Regex returns byte offsets → convert to codepoints
  # so the slice offsets line up with `build_segments`.
  defp locate(text, quote) do
    pattern =
      quote
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&Regex.escape/1)
      |> Enum.join("\\s+")

    with true <- pattern != "",
         [{byte_start, byte_len} | _] <- Regex.run(~r/#{pattern}/u, text, return: :index) do
      start = text |> binary_part(0, byte_start) |> String.length()
      matched = binary_part(text, byte_start, byte_len)
      {start, start + String.length(matched)}
    else
      _ -> nil
    end
  end

  # ── Notes widget ─────────────────────────────────────────────────────────────

  defp visible_claims(%{claims: claims}) when is_list(claims),
    do: Enum.reject(claims, &(&1["position"] in @hidden_positions))

  defp visible_claims(_), do: []

  defp saved?(saved_keys, study_id, claim_id),
    do: MapSet.member?(saved_keys, {study_id, claim_id})

  defp endpoint(claim, side),
    do: claim["#{side}_label"] || claim["#{side}_name"] || claim["#{side}_text"]

  # Same-page scroll anchor to the claim's first evidence paragraph (the inline
  # <mark> highlight lives there); nil when the claim carries no paragraph.
  defp claim_anchor(%{"evidence" => [%{"paragraph_id" => pid} | _]}) when is_binary(pid),
    do: "#par-#{pid}"

  defp claim_anchor(_), do: nil

  # Same-page scroll anchor to the paragraph a note marked (so its title jumps to
  # the highlighted passage); nil for notes with no captured paragraph.
  defp note_anchor(%{paragraph_id: pid}) when is_binary(pid), do: "#par-#{pid}"
  defp note_anchor(_), do: nil

  # ── Section headings ─────────────────────────────────────────────────────────
  # The authors' numbering ("2.1. …") drives the visual hierarchy: subsections are
  # indented and set quieter, with the number emphasized as a spine.

  defp raw_section_title(%{"title" => t, "index" => i}) when t in [nil, ""],
    do: "Section #{(i || 0) + 1}"

  defp raw_section_title(%{"title" => t}) when is_binary(t) and t != "", do: t
  defp raw_section_title(_), do: "Section"

  # {number_string | nil, label} parsed off the heading text.
  defp section_parts(section) do
    case Regex.run(~r/^\s*(\d+(?:\.\d+)*)\.?\s+(.*\S)\s*$/, raw_section_title(section)) do
      [_, number, rest] -> {number, rest}
      _ -> {nil, raw_section_title(section)}
    end
  end

  defp section_number(section), do: elem(section_parts(section), 0)
  defp section_label(section), do: elem(section_parts(section), 1)

  # A subsection is any heading numbered with a dot ("2.1", "3.4.2").
  defp subsection?(section) do
    case section_number(section) do
      nil -> false
      number -> String.contains?(number, ".")
    end
  end

  defp subsection_indent(section), do: if(subsection?(section), do: "ml-4 md:ml-6", else: "")

  defp title(%{title: t}) when is_binary(t) and t != "", do: t
  defp title(_), do: "Untitled"

  defp pubmed_url(%{pmid: pmid}) when is_integer(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp pubmed_url(_), do: "https://pubmed.ncbi.nlm.nih.gov/"

  defp journal(%{journal: j}) when is_binary(j) and j != "", do: j
  defp journal(_), do: nil

  defp authors_line(%{authors: authors}) when is_list(authors) and authors != [] do
    case authors do
      [a] -> a
      [a, b] -> "#{a}, #{b}"
      [a, b | _] -> "#{a}, #{b}, et al."
    end
  end

  defp authors_line(_), do: nil
end
