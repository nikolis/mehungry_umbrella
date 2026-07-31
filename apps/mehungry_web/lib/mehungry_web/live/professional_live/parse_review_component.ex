defmodule MehungryWeb.ProfessionalLive.ParseReviewComponent do
  @moduledoc """
  Human-review queue for structured description parses produced by the
  deterministic USDA parser. Lists `Food.list_pending_parse_review/1` (status
  `candidate`, current parser version, lowest-confidence first) and lets an
  admin Edit the parsed fields inline, then Verify or Reject each row.
  Verifying links the (possibly edited) canonical food into the lexicon.

  Self-contained: its streams, pagination and events are `phx-target={@myself}`
  so they never collide with the host `SciencePipeline` LiveView.
  """
  use MehungryWeb, :live_component

  alias Mehungry.Food

  @per_page 25

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:page, fn -> 1 end)
      |> assign_new(:skipped_page, fn -> 1 end)
      |> assign_new(:suggestion_page, fn -> 1 end)
      |> assign_new(:editing_id, fn -> nil end)
      |> assign_new(:editing, fn -> nil end)
      |> assign_new(:edit_values, fn -> %{} end)
      |> assign_new(:streamed, fn -> false end)

    socket =
      if socket.assigns.streamed do
        socket
      else
        socket
        |> assign(:streamed, true)
        |> stream(:parses, Food.list_pending_parse_review(limit: @per_page, offset: 0))
        |> stream(:suggestions, Food.list_pending_parser_suggestions(limit: @per_page, offset: 0))
        |> stream(:skipped, Food.list_skipped_parses(limit: @per_page, offset: 0))
      end

    {:ok, socket}
  end

  # Rows live inside a `phx-update="stream"` container, so a row only
  # re-renders when re-inserted — every edit-state change stream_inserts the
  # affected row(s).
  @impl true
  def handle_event("edit", %{"id" => id}, socket) do
    parsed = Food.get_parsed_food!(String.to_integer(id))
    previous = socket.assigns.editing

    socket =
      socket
      |> assign(:editing_id, parsed.id)
      |> assign(:editing, parsed)
      |> assign(:edit_values, %{
        "canonical_food_text" => parsed.canonical_food_text,
        "harvest_stage" => parsed.harvest_stage,
        "processing" => Enum.join(parsed.processing, ", "),
        "processing_modifiers" => Enum.join(parsed.processing_modifiers, ", "),
        "packaging" => parsed.packaging,
        "part" => parsed.part,
        "dismemberment" => parsed.dismemberment,
        "bone_state" => parsed.bone_state,
        "portion" => Enum.join(parsed.portion, ", "),
        "grade" => parsed.grade,
        "fat" => parsed.fat,
        "notes" => parsed.notes
      })
      |> stream_insert(:parses, parsed)

    socket =
      if previous && previous.id != parsed.id do
        stream_insert(socket, :parses, previous)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-edit", _params, socket) do
    previous = socket.assigns.editing

    socket =
      socket |> assign(:editing_id, nil) |> assign(:editing, nil) |> assign(:edit_values, %{})

    socket = if previous, do: stream_insert(socket, :parses, previous), else: socket
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"parsed_food_id" => id, "parsed_food" => params}, socket) do
    id = String.to_integer(id)

    attrs = %{
      canonical_food_text: params["canonical_food_text"],
      harvest_stage: params["harvest_stage"],
      processing: split_list(params["processing"]),
      processing_modifiers: split_list(params["processing_modifiers"]),
      packaging: params["packaging"],
      part: blank_to_nil(params["part"]),
      dismemberment: blank_to_nil(params["dismemberment"]),
      bone_state: blank_to_nil(params["bone_state"]),
      portion: split_list(params["portion"]),
      grade: blank_to_nil(params["grade"]),
      fat: blank_to_nil(params["fat"]),
      notes: params["notes"]
    }

    case Food.update_parsed_candidate(id, attrs) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:editing_id, nil)
         |> assign(:editing, nil)
         |> assign(:edit_values, %{})
         |> stream_insert(:parses, Food.get_parsed_food!(id))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not save — check the edited values")}
    end
  end

  @impl true
  def handle_event("verify", %{"id" => id}, socket) do
    {:ok, _} = Food.verify_parsed_food(String.to_integer(id), socket.assigns[:current_user_id])

    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:editing, nil)
     |> stream_delete_by_dom_id(:parses, "parses-#{id}")}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_parsed_food(String.to_integer(id))

    {:noreply,
     socket
     |> assign(:editing_id, nil)
     |> assign(:editing, nil)
     |> stream_delete_by_dom_id(:parses, "parses-#{id}")}
  end

  @impl true
  def handle_event("accept-suggestion", %{"id" => id}, socket) do
    case Food.accept_parser_suggestion(String.to_integer(id), socket.assigns[:current_user_id]) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Alias added — re-parse the ingredient to resolve it.")
         |> stream_delete_by_dom_id(:suggestions, "suggestions-#{id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not accept suggestion (#{inspect(reason)})")}
    end
  end

  @impl true
  def handle_event("reject-suggestion", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_parser_suggestion(String.to_integer(id))
    {:noreply, stream_delete_by_dom_id(socket, :suggestions, "suggestions-#{id}")}
  end

  @impl true
  def handle_event("load-more-suggestions", _params, socket) do
    page = socket.assigns.suggestion_page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:suggestion_page, page)
     |> stream(
       :suggestions,
       Food.list_pending_parser_suggestions(limit: @per_page, offset: offset)
     )}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(:parses, Food.list_pending_parse_review(limit: @per_page, offset: offset))}
  end

  @impl true
  def handle_event("load-more-skipped", _params, socket) do
    page = socket.assigns.skipped_page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:skipped_page, page)
     |> stream(:skipped, Food.list_skipped_parses(limit: @per_page, offset: offset))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <h2 class="text-lg font-medium text-parchment mb-2">Parsed foods</h2>
      <p class="text-parchment-dim text-sm mb-3">
        Structured parses of USDA descriptions awaiting sign-off, lowest confidence first.
        <span class="font-medium">Edit</span>
        to correct any field, then <span class="font-medium">Verify</span>
        to accept it into the canonical-food lexicon; <span class="font-medium">Reject</span>
        dismisses it. Both leave the queue.
      </p>

      <div id={"#{@id}-list"} phx-update="stream" class="divide-y divide-ink-panel2">
        <div :for={{dom_id, parsed} <- @streams.parses} id={dom_id} class="py-3">
          <div class="flex flex-wrap items-center gap-3 justify-between">
            <div class="min-w-0 flex-1">
              <div class="text-parchment font-medium truncate">
                {parsed.ingredient.name}
                <span class="text-parchment-dim">→</span>
                <em>{parsed.canonical_food_text}</em>
              </div>
              <div class="text-xs text-parchment-dim">
                stage: {parsed.harvest_stage} · processing: {list_label(parsed.processing)} · modifiers: {list_label(
                  parsed.processing_modifiers
                )} · packaging: {parsed.packaging} · part: {value_label(parsed.part)} · dismemberment: {value_label(
                  parsed.dismemberment
                )} · bone: {value_label(parsed.bone_state)} · portion: {list_label(parsed.portion)} · grade: {value_label(
                  parsed.grade
                )} · fat: {value_label(parsed.fat)} · confidence: {confidence_label(parsed.confidence)}
              </div>
              <details :if={parsed.trace} class="mt-1">
                <summary class="text-xs text-parchment-dim cursor-pointer">trace</summary>
                <pre class="text-xs text-parchment-dim overflow-x-auto mt-1">{trace_label(parsed.trace)}</pre>
              </details>
            </div>

            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="edit"
                phx-value-id={parsed.id}
                phx-target={@myself}
                class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
              >
                Edit
              </button>
              <button
                type="button"
                phx-click="verify"
                phx-value-id={parsed.id}
                phx-target={@myself}
                class="px-3 py-1.5 rounded bg-basil text-ink text-sm font-medium hover:opacity-90"
              >
                Verify
              </button>
              <button
                type="button"
                phx-click="reject"
                phx-value-id={parsed.id}
                phx-target={@myself}
                data-confirm="Reject this parse? The ingredient keeps no structured food."
                class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
              >
                Reject
              </button>
            </div>
          </div>

          <form
            :if={@editing_id == parsed.id}
            phx-submit="save"
            phx-target={@myself}
            class="mt-3 grid gap-2 sm:grid-cols-2 rounded border border-ink-panel2 p-3"
          >
            <input type="hidden" name="parsed_food_id" value={parsed.id} />

            <label class="text-xs text-parchment-dim">
              Canonical food
              <input
                type="text"
                name="parsed_food[canonical_food_text]"
                value={@edit_values["canonical_food_text"]}
                required
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Harvest stage
              <input
                type="text"
                name="parsed_food[harvest_stage]"
                value={@edit_values["harvest_stage"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Processing (comma-separated)
              <input
                type="text"
                name="parsed_food[processing]"
                value={@edit_values["processing"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Modifiers (comma-separated)
              <input
                type="text"
                name="parsed_food[processing_modifiers]"
                value={@edit_values["processing_modifiers"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Packaging
              <input
                type="text"
                name="parsed_food[packaging]"
                value={@edit_values["packaging"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Part
              <input
                type="text"
                name="parsed_food[part]"
                value={@edit_values["part"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Dismemberment
              <input
                type="text"
                name="parsed_food[dismemberment]"
                value={@edit_values["dismemberment"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Bone state
              <input
                type="text"
                name="parsed_food[bone_state]"
                value={@edit_values["bone_state"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Portion (comma-separated)
              <input
                type="text"
                name="parsed_food[portion]"
                value={@edit_values["portion"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Grade
              <input
                type="text"
                name="parsed_food[grade]"
                value={@edit_values["grade"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Fat
              <input
                type="text"
                name="parsed_food[fat]"
                value={@edit_values["fat"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <label class="text-xs text-parchment-dim">
              Notes
              <input
                type="text"
                name="parsed_food[notes]"
                value={@edit_values["notes"]}
                class="mt-1 w-full rounded border border-ink-panel2 bg-ink-panel px-2 py-1 text-sm text-parchment"
              />
            </label>

            <div class="sm:col-span-2 flex items-center gap-2">
              <button
                type="submit"
                class="px-3 py-1.5 rounded bg-basil text-ink text-sm font-medium hover:opacity-90"
              >
                Save
              </button>
              <button
                type="button"
                phx-click="cancel-edit"
                phx-target={@myself}
                class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      </div>

      <div class="mt-4 flex items-center gap-3">
        <button
          type="button"
          phx-click="load-more"
          phx-target={@myself}
          class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
        >
          Load more
        </button>
        <span class="text-parchment-dim text-xs">
          Verified and rejected rows leave this list. Nothing here means the queue is clear.
        </span>
      </div>

      <div class="mt-8 border-t border-ink-panel2 pt-6">
        <h3 class="text-base font-medium text-parchment mb-2">Semantic suggestions</h3>
        <p class="text-parchment-dim text-sm mb-3">
          For low-confidence parses whose head noun missed the vocabulary, the
          embedding model proposes the nearest existing canonical food.
          <span class="font-medium">Accept</span>
          records the alias (surface → canonical) so the next parse resolves;
          <span class="font-medium">Reject</span>
          dismisses it. Empty unless embeddings are enabled and canonical foods
          are embedded.
        </p>

        <div id={"#{@id}-suggestions"} phx-update="stream" class="divide-y divide-ink-panel2">
          <div
            :for={{dom_id, s} <- @streams.suggestions}
            id={dom_id}
            class="py-3 flex flex-wrap items-center gap-3 justify-between"
          >
            <div class="min-w-0 flex-1">
              <div class="text-parchment font-medium truncate">
                <em>{s.surface_text}</em>
                <span class="text-parchment-dim">≈</span>
                {s.suggested_target}
                <span class="text-xs text-parchment-dim">({score_label(s.score)})</span>
              </div>
              <div
                :if={s.ingredient_parsed_food && s.ingredient_parsed_food.ingredient}
                class="text-xs text-parchment-dim truncate"
              >
                from: {s.ingredient_parsed_food.ingredient.name}
              </div>
            </div>

            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="accept-suggestion"
                phx-value-id={s.id}
                phx-target={@myself}
                class="px-3 py-1.5 rounded bg-basil text-ink text-sm font-medium hover:opacity-90"
              >
                Accept
              </button>
              <button
                type="button"
                phx-click="reject-suggestion"
                phx-value-id={s.id}
                phx-target={@myself}
                class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
              >
                Reject
              </button>
            </div>
          </div>
        </div>

        <div class="mt-4 flex items-center gap-3">
          <button
            type="button"
            phx-click="load-more-suggestions"
            phx-target={@myself}
            class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
          >
            Load more
          </button>
          <span class="text-parchment-dim text-xs">
            Accepting grows the parser vocabulary; nothing here means no pending suggestions.
          </span>
        </div>
      </div>

      <div class="mt-8 border-t border-ink-panel2 pt-6">
        <h3 class="text-base font-medium text-parchment mb-2">Skipped (not a food)</h3>
        <p class="text-parchment-dim text-sm mb-3">
          Descriptions the parser deliberately skipped, and why. Read-only —
          nothing to action here.
        </p>

        <div id={"#{@id}-skipped"} phx-update="stream" class="divide-y divide-ink-panel2">
          <div
            :for={{dom_id, parsed} <- @streams.skipped}
            id={dom_id}
            class="py-3 flex flex-wrap items-center gap-3 justify-between"
          >
            <div class="min-w-0 flex-1">
              <div class="text-parchment font-medium truncate">
                {parsed.ingredient.name}
              </div>
              <div class="text-xs text-parchment-dim">
                {reason_label(parsed.skip_reason)}
              </div>
            </div>
            <span class="text-xs font-medium text-parchment-dim">
              {parsed.skip_reason}
            </span>
          </div>
        </div>

        <div class="mt-4 flex items-center gap-3">
          <button
            type="button"
            phx-click="load-more-skipped"
            phx-target={@myself}
            class="px-3 py-1.5 rounded border border-ink-panel2 text-parchment text-sm font-medium hover:opacity-90"
          >
            Load more
          </button>
          <span class="text-parchment-dim text-xs">
            Empty means every parsed description was a food.
          </span>
        </div>
      </div>
    </section>
    """
  end

  # ── View helpers ───────────────────────────────────────────────────────────

  defp split_list(nil), do: []

  defp split_list(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp value_label(nil), do: "—"
  defp value_label(value), do: value

  defp confidence_label(nil), do: "—"
  defp confidence_label(c) when is_float(c), do: :erlang.float_to_binary(c, decimals: 2)
  defp confidence_label(c), do: to_string(c)

  defp score_label(s) when is_float(s), do: :erlang.float_to_binary(s, decimals: 2)
  defp score_label(s), do: to_string(s)

  defp list_label([]), do: "—"
  defp list_label(list), do: Enum.join(list, ", ")

  defp trace_label(trace) do
    Enum.map_join(trace, "\n", &inspect(&1, pretty: true, width: 80))
  end

  defp reason_label("not_food"), do: "Not a food (e.g. alcoholic beverage)"
  defp reason_label("prepared_dish"), do: "Prepared/composite dish (e.g. commercial, homemade)"
  defp reason_label(other), do: other
end
