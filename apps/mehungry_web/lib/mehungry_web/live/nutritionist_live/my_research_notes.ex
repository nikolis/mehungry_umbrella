defmodule MehungryWeb.NutritionistLive.MyResearchNotes do
  @moduledoc """
  The nutritionist's own **research notes** (`/nutritionist/research/notes`) —
  the saved suggestions + custom notes captured from the research search
  (`ResearchCondition`). Grouped by condition, each note links back to its source
  passage in the in-app reader (or PubMed when there's no full-text anchor) and
  can be deleted. Private to the owning nutritionist.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Professionals.ResearchNotes

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_notes(socket)}
  end

  @impl true
  def handle_event("delete_note", %{"id" => id}, socket) do
    {:ok, _} = ResearchNotes.delete_note(socket.assigns.current_user.id, String.to_integer(id))
    {:noreply, socket |> assign_notes() |> put_flash(:info, "Note removed.")}
  end

  defp assign_notes(socket) do
    notes = ResearchNotes.list_for_user(socket.assigns.current_user.id)

    socket
    |> assign(:page_title, "My research notes")
    |> assign(:count, length(notes))
    |> assign(:grouped, group_by_condition(notes))
  end

  # [{condition_or_nil, [note]}] in the notes' existing (newest-first) order.
  defp group_by_condition(notes) do
    notes
    |> Enum.group_by(& &1.condition)
    |> Enum.sort_by(fn {condition, _} -> condition_name(condition) end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <.link
        navigate={~p"/nutritionist/research"}
        class="inline-flex items-center gap-1 text-sm text-parchment-dim hover:text-parchment mb-3"
      >
        <.icon name="hero-arrow-left" class="w-4 h-4" /> All research
      </.link>

      <header class="mb-6">
        <h1 class="text-2xl font-semibold text-parchment">My research notes</h1>
        <p class="text-sm text-parchment-dim mt-1">
          {@count} saved note{if @count == 1, do: "", else: "s"} from the research search.
        </p>
      </header>

      <p :if={@count == 0} class="text-sm text-parchment-dim py-8 text-center">
        No saved notes yet. Open a condition's research and use <strong>Save</strong>
        on a suggested note, or write your own.
      </p>

      <section :for={{condition, notes} <- @grouped} class="mb-8">
        <h2 class="text-xs font-semibold uppercase tracking-wide text-parchment-dim mb-3">
          {condition_name(condition)}
        </h2>

        <article
          :for={note <- notes}
          class="mb-3 p-4 rounded-xl bg-ink-panel2 border border-ink-panel2"
        >
          <div class="flex items-start justify-between gap-3">
            <span class={[
              "text-[10px] px-2 py-0.5 rounded-full",
              if(note.kind == "custom",
                do: "bg-paprika/15 text-paprika-soft",
                else: "bg-basil/15 text-basil"
              )
            ]}>
              {if note.kind == "custom", do: "My note", else: "Suggested"}
            </span>
            <button
              type="button"
              phx-click="delete_note"
              phx-value-id={note.id}
              data-confirm="Remove this note?"
              class="text-parchment-dim hover:text-paprika"
              aria-label="Remove note"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>

          <p class="text-sm text-parchment mt-2">{note.body}</p>

          <p :if={note.quoted_text} class="text-xs text-parchment-dim/80 italic mt-1">
            “{note.quoted_text}”
          </p>

          <div class="flex flex-wrap items-center gap-3 mt-2 text-xs">
            <span :if={note.study} class="text-parchment-dim">
              {note.study.title}
            </span>
            <.link
              :if={reader_link(note)}
              navigate={reader_link(note)}
              class="inline-flex items-center gap-0.5 text-basil hover:underline"
            >
              <.icon name="hero-arrow-top-right-on-square" class="w-3 h-3" /> Open in text
            </.link>
            <a
              :if={is_nil(reader_link(note)) and pubmed_link(note)}
              href={pubmed_link(note)}
              target="_blank"
              rel="noopener"
              class="text-basil hover:underline"
            >
              source
            </a>
          </div>
        </article>
      </section>
    </div>
    """
  end

  defp condition_name(nil), do: "Unlinked"
  defp condition_name(condition), do: condition.name

  # Deep-link back to the in-app reader when we captured a paragraph anchor and
  # still know the condition + study it belongs to.
  defp reader_link(%{condition_id: cid, study_id: sid, paragraph_id: pid})
       when is_integer(cid) and is_integer(sid) and is_binary(pid) do
    ~p"/nutritionist/research/#{cid}/paper/#{sid}" <> "#par-#{pid}"
  end

  defp reader_link(_), do: nil

  defp pubmed_link(%{study: %{pmid: pmid}}) when is_integer(pmid),
    do: "https://pubmed.ncbi.nlm.nih.gov/#{pmid}/"

  defp pubmed_link(_), do: nil
end
