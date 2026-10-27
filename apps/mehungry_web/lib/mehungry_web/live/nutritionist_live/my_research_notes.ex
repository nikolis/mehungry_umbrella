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
  alias Mehungry.Health

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  # A `condition_id` query param (e.g. from a client overview) scopes the page to
  # the notes saved under that one condition.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign_notes(socket, params["condition_id"])}
  end

  @impl true
  def handle_event("delete_note", %{"id" => id}, socket) do
    {:ok, _} = ResearchNotes.delete_note(socket.assigns.current_user.id, String.to_integer(id))
    condition_id = socket.assigns.filter_condition && to_string(socket.assigns.filter_condition.id)
    {:noreply, socket |> assign_notes(condition_id) |> put_flash(:info, "Note removed.")}
  end

  defp assign_notes(socket, condition_id) do
    {condition, notes} = scoped_notes(socket.assigns.current_user.id, condition_id)

    socket
    |> assign(:page_title, if(condition, do: "My notes · #{condition.name}", else: "My research notes"))
    |> assign(:filter_condition, condition)
    |> assign(:count, length(notes))
    |> assign(:grouped, group_by_condition(notes))
  end

  # A valid `condition_id` filters to that condition's notes; anything else (blank,
  # non-integer, unknown id) falls back to the full list.
  defp scoped_notes(user_id, condition_id) when is_binary(condition_id) and condition_id != "" do
    case Integer.parse(condition_id) do
      {id, _} ->
        case Health.get_condition(id) do
          nil -> {nil, ResearchNotes.list_for_user(user_id)}
          condition -> {condition, ResearchNotes.list_for_user_and_condition(user_id, id)}
        end

      :error ->
        {nil, ResearchNotes.list_for_user(user_id)}
    end
  end

  defp scoped_notes(user_id, _), do: {nil, ResearchNotes.list_for_user(user_id)}

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
        <h1 class="text-2xl font-semibold text-parchment">
          My research notes<span :if={@filter_condition} class="text-parchment-dim font-normal"> · {@filter_condition.name}</span>
        </h1>
        <p class="text-sm text-parchment-dim mt-1">
          {@count} saved note{if @count == 1, do: "", else: "s"}<span :if={@filter_condition}> for {@filter_condition.name}</span>.
        </p>
        <.link
          :if={@filter_condition}
          navigate={~p"/nutritionist/research/notes"}
          class="inline-flex items-center gap-1 text-xs text-basil hover:underline mt-1"
        >
          View all notes
        </.link>
      </header>

      <div :if={@count == 0} class="text-sm text-parchment-dim py-8 text-center">
        <%= if @filter_condition do %>
          <p>No notes saved for {@filter_condition.name} yet.</p>
          <.link
            navigate={~p"/nutritionist/research/#{@filter_condition.id}"}
            class="inline-flex items-center gap-1 text-basil hover:underline mt-2"
          >
            Open {@filter_condition.name} research <.icon name="hero-arrow-right" class="w-4 h-4" />
          </.link>
        <% else %>
          <p>
            No saved notes yet. Open a condition's research and use <strong>Save</strong>
            on a suggested note, or write your own.
          </p>
        <% end %>
      </div>

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
