defmodule MehungryWeb.ProfessionalLive.SpeciesEnrichmentReview do
  @moduledoc """
  Admin front door for species enrichment (Wikidata CC0 + FAOSTAT CC BY) — see
  `docs/implementation/science/species_enrichment.md`.

  Two jobs on one page:

    * **Fetch** — "Enrich all species" fans out one
      `Mehungry.ObanWorkers.SpeciesEnrichmentWorker` job per `FoundementalFoodSpecies`
      on the `:species_enrichment` queue and this view watches the batch finish live
      (per-species rows streamed + patched O(1) from PubSub, the high-frequency
      `processing` signal coalesced behind a flush timer — the
      `oban_ui_connected_worker.md` pattern). The production trigger for
      `mix species.enrich`.
    * **Review** — FAOSTAT facts auto-promote on fetch; Wikidata facts land `pending`
      and an admin promotes (surfaces on the species page) or rejects (sticky — a
      re-fetch won't resurrect it) here, individually or via "Promote all pending".
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesEnrichmentRuns, as: Runs

  @flush_ms 400

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Mehungry.PubSub, Runs.topic())

    batch_id = Runs.latest_batch_id()

    socket =
      socket
      |> assign(:page_title, "Species enrichment")
      |> assign(:batch_id, batch_id)
      |> assign(:counts, Runs.counts_for_batch(batch_id))
      |> assign(:enriching?, false)
      |> assign(:processing_ids, MapSet.new())
      |> assign(:flush_scheduled?, false)
      |> assign(:suggestions, %{})
      |> stream(:rows, Runs.list_batch_rows(batch_id))
      |> load_species()
      |> load_review()

    {:ok, socket}
  end

  # The FAOSTAT crosswalk list — all species + how many already carry a code.
  defp load_species(socket) do
    species = Food.list_foundemental_species()

    socket
    |> assign(:species, species)
    |> assign(:coded_count, Enum.count(species, & &1.faostat_item_code))
  end

  # The pending-review list (and promoted count). Kept separate from the run stream.
  defp load_review(socket) do
    pending = Food.list_pending_species_facts(limit: 500)

    socket
    |> assign(:groups, Enum.group_by(pending, & &1.species.name))
    |> assign(:pending_count, length(pending))
    |> assign(:promoted_count, Food.count_promoted_species_facts())
  end

  # ── Triggers ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("enrich_all", _params, socket) do
    {:noreply,
     socket
     |> assign(:enriching?, true)
     |> start_async(:enrich_all, fn -> Runs.enrich_all_species() end)}
  end

  def handle_event("cancel", _params, socket) do
    Runs.cancel_batch(socket.assigns.batch_id)
    {:noreply, reload_batch(socket, socket.assigns.batch_id)}
  end

  def handle_event("promote", %{"id" => id}, socket) do
    Food.promote_species_fact(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Promoted — it now shows on the species page.") |> load_review()}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    Food.reject_species_fact(String.to_integer(id))
    {:noreply, socket |> put_flash(:info, "Rejected.") |> load_review()}
  end

  def handle_event("promote_all", _params, socket) do
    n = Food.promote_all_pending_species_facts()
    {:noreply, socket |> put_flash(:info, "Promoted #{n} pending fact#{if n == 1, do: "", else: "s"}.") |> load_review()}
  end

  # ── FAOSTAT crosswalk ──────────────────────────────────────────────────────────

  def handle_event("suggest_faostat", _params, socket) do
    suggestions = Food.suggest_faostat_codes(socket.assigns.species)

    socket =
      if suggestions == %{} do
        put_flash(socket, :error, "Couldn't read the bundled FAOSTAT item list.")
      else
        put_flash(socket, :info, "Suggested a FAOSTAT item code for each species — verify or edit, then Save.")
      end

    {:noreply, assign(socket, :suggestions, suggestions)}
  end

  def handle_event("save_faostat_code", %{"species_id" => id, "code" => code}, socket) do
    {:noreply, save_faostat_code(socket, id, code)}
  end

  def handle_event("apply_suggestion", %{"species-id" => id}, socket) do
    code = get_in(socket.assigns.suggestions, [String.to_integer(id), :code])
    {:noreply, save_faostat_code(socket, id, code)}
  end

  # Set (or clear, when blank) a species' `faostat_item_code`, then refresh the list.
  defp save_faostat_code(socket, id, code) do
    code = code |> to_string() |> String.trim()
    code = if code == "", do: nil, else: code

    species = Food.get_foundemental_species!(String.to_integer(id))

    case Food.update_foundemental_species(species, %{faostat_item_code: code}) do
      {:ok, updated} ->
        label = if is_nil(code), do: "Cleared", else: "Saved #{code}"

        socket
        |> put_flash(:info, "#{label} for #{updated.name}.")
        |> load_species()

      {:error, _changeset} ->
        put_flash(socket, :error, "Couldn't save the code for #{species.name}.")
    end
  end

  # ── Async results ────────────────────────────────────────────────────────────

  @impl true
  def handle_async(:enrich_all, {:ok, {:ok, batch_id}}, socket) do
    {:noreply,
     socket
     |> assign(:enriching?, false)
     |> put_flash(:info, "Enrichment started — watch each species finish below")
     |> reload_batch(batch_id)}
  end

  def handle_async(:enrich_all, {:ok, {:error, :no_species}}, socket) do
    {:noreply, socket |> assign(:enriching?, false) |> put_flash(:error, "No species to enrich")}
  end

  def handle_async(:enrich_all, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:enriching?, false)
     |> put_flash(:error, "Could not start enrichment — #{inspect(reason)}")}
  end

  # ── Live progress ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:enrichment_run, run}, socket) do
    if run.batch_id == socket.assigns.batch_id do
      {:noreply,
       socket
       |> stream_insert(:rows, run)
       |> assign(:counts, Runs.counts_for_batch(socket.assigns.batch_id))
       # New facts land as the batch runs — refresh the review list so FAOSTAT
       # auto-promotions and fresh pending Wikidata facts show up without a reload.
       |> load_review()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:enrichment_processing, batch_id, species_id}, socket) do
    if batch_id == socket.assigns.batch_id do
      {:noreply, socket |> buffer_processing(species_id) |> maybe_schedule_flush()}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:flush_processing, socket) do
    ids = MapSet.to_list(socket.assigns.processing_ids)

    socket =
      socket
      |> assign(:processing_ids, MapSet.new())
      |> assign(:flush_scheduled?, false)

    socket =
      Runs.list_batch_rows(socket.assigns.batch_id)
      |> Enum.filter(&(&1.foundemental_species_id in ids))
      |> Enum.reduce(socket, fn row, acc -> stream_insert(acc, :rows, row) end)

    {:noreply, assign(socket, :counts, Runs.counts_for_batch(socket.assigns.batch_id))}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp reload_batch(socket, batch_id) do
    socket
    |> assign(:batch_id, batch_id)
    |> assign(:counts, Runs.counts_for_batch(batch_id))
    |> stream(:rows, Runs.list_batch_rows(batch_id), reset: true)
  end

  defp buffer_processing(socket, species_id),
    do: update(socket, :processing_ids, &MapSet.put(&1, species_id))

  defp maybe_schedule_flush(socket) do
    if socket.assigns.flush_scheduled? do
      socket
    else
      Process.send_after(self(), :flush_processing, @flush_ms)
      assign(socket, :flush_scheduled?, true)
    end
  end

  defp in_flight?(counts), do: counts.pending + counts.processing > 0

  # ── View ─────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-semibold mb-1">Species enrichment</h1>
      <p class="text-sm text-gray-500 mb-6">
        Fetch provenance-cited facts per food species from Wikidata (CC0) and FAOSTAT (CC BY 4.0,
        credited on the page). FAOSTAT facts auto-promote; Wikidata facts need review before they
        surface on the species page (a top-hit for an ambiguous name can be wrong).
      </p>

      <%!-- ── Fetch trigger + live progress ──────────────────────────────────── --%>
      <section class="rounded-lg border border-gray-200 bg-gray-50 p-4 mb-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="text-sm text-gray-600">
            One job per species on the <code>:species_enrichment</code> queue — watch each finish below.
          </div>
          <div class="flex items-center gap-2">
            <button
              :if={in_flight?(@counts)}
              phx-click="cancel"
              data-confirm="Cancel the remaining species in this batch?"
              class="rounded-md bg-red-50 text-red-700 px-3 py-1.5 text-sm hover:bg-red-100"
            >
              Cancel batch
            </button>
            <button
              phx-click="enrich_all"
              disabled={@enriching? or in_flight?(@counts)}
              class="rounded-md bg-green-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-40 disabled:cursor-not-allowed"
            >
              {if @enriching? or in_flight?(@counts), do: "Enriching…", else: "Enrich all species"}
            </button>
          </div>
        </div>

        <div class="mt-3 flex flex-wrap gap-4 text-sm">
          <span class="text-gray-500">Pending <span class="text-gray-800 font-medium">{@counts.pending}</span></span>
          <span class="text-gray-500">Processing <span class="text-amber-600 font-medium">{@counts.processing}</span></span>
          <span class="text-gray-500">Completed <span class="text-green-700 font-medium">{@counts.completed}</span></span>
          <span class="text-gray-500">Failed <span class="text-red-600 font-medium">{@counts.failed}</span></span>
          <span class="text-gray-500 ml-auto">Facts fetched <span class="text-gray-800 font-medium">{@counts.facts_total}</span></span>
        </div>

        <div id="enrichment-rows" phx-update="stream" class="mt-3 divide-y divide-gray-200">
          <div
            :for={{dom_id, row} <- @streams.rows}
            id={dom_id}
            class="flex flex-wrap items-center gap-3 py-2 text-sm"
          >
            <span class="min-w-[12rem] text-gray-800">{row.species.name}</span>
            <span class={"inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{status_badge_class(row.status)}"}>
              {row.status}
            </span>
            <span :if={row.status == "completed"} class="text-xs text-gray-500">
              {row.wikidata_count} Wikidata · {row.faostat_count} FAOSTAT
            </span>
            <span
              :if={row.status == "failed" and row.error}
              class="text-xs text-red-600 truncate max-w-[20rem]"
              title={row.error}
            >
              {row.error}
            </span>
          </div>
        </div>

        <p :if={@counts.total == 0} class="mt-3 text-sm text-gray-500">
          No batch yet — click <span class="font-medium">Enrich all species</span> to start.
        </p>
      </section>

      <%!-- ── FAOSTAT crosswalk ─────────────────────────────────────────────── --%>
      <section class="rounded-lg border border-gray-200 bg-gray-50 p-4 mb-8">
        <div class="flex flex-wrap items-center justify-between gap-3 mb-1">
          <h2 class="text-lg font-semibold">FAOSTAT crosswalk</h2>
          <div class="flex items-center gap-3 text-sm">
            <span class="text-gray-500">{@coded_count} / {length(@species)} coded</span>
            <button
              phx-click="suggest_faostat"
              class="rounded-md bg-blue-600 px-3 py-1.5 font-medium text-white hover:bg-blue-700"
            >
              Run suggester
            </button>
          </div>
        </div>
        <p class="text-sm text-gray-500 mb-4">
          FAOSTAT facts only fetch for a species with an <code>item_code</code>. Run the suggester to
          fuzzy-match each species name to a FAOSTAT crop item, then verify/edit the code and Save
          (blank clears it). FAOSTAT names are crop-level, so a suggestion is a hint — confirm it.
        </p>

        <ul class="divide-y divide-gray-200">
          <li
            :for={sp <- @species}
            class="flex flex-wrap items-center gap-x-4 gap-y-2 py-2.5 text-sm"
          >
            <div class="min-w-[12rem]">
              <span class="text-gray-800">{sp.name}</span>
              <span :if={sp.scientific_name} class="text-xs text-gray-400 italic ml-1">
                {sp.scientific_name}
              </span>
            </div>

            <form phx-submit="save_faostat_code" class="flex items-center gap-2">
              <input type="hidden" name="species_id" value={sp.id} />
              <input
                type="text"
                name="code"
                value={sp.faostat_item_code}
                placeholder="—"
                class="w-28 rounded-md border-gray-300 text-sm py-1"
              />
              <button class="rounded-md border border-gray-300 bg-white px-3 py-1.5 font-medium text-gray-700 hover:bg-gray-50">
                Save
              </button>
            </form>

            <div :if={suggestion = @suggestions[sp.id]} class="flex items-center gap-2 text-xs text-gray-500">
              <span>
                → <span class="font-mono text-gray-700">{suggestion.code}</span>
                {suggestion.item}
                <span class={score_class(suggestion.score)}>({Float.round(suggestion.score, 2)})</span>
              </span>
              <button
                phx-click="apply_suggestion"
                phx-value-species-id={sp.id}
                class="rounded-md bg-green-600 px-2.5 py-1 font-medium text-white hover:bg-green-700"
              >
                Apply
              </button>
            </div>
          </li>
        </ul>
      </section>

      <%!-- ── Wikidata review queue ──────────────────────────────────────────── --%>
      <div class="flex items-baseline justify-between mb-3">
        <h2 class="text-lg font-semibold">Pending review (Wikidata)</h2>
        <div class="flex items-center gap-3 text-sm">
          <span class="text-gray-500">{@pending_count} pending · {@promoted_count} promoted</span>
          <button
            :if={@pending_count > 0}
            phx-click="promote_all"
            data-confirm="Promote all #{@pending_count} pending facts?"
            class="rounded-md bg-green-600 px-3 py-1.5 font-medium text-white hover:bg-green-700"
          >
            Promote all pending ({@pending_count})
          </button>
        </div>
      </div>

      <div :if={@groups == %{}} class="text-gray-500 py-12 text-center">
        Nothing pending. Click <span class="font-medium">Enrich all species</span> above (or run
        <code>mix species.enrich</code>) to fetch facts.
      </div>

      <div :for={{species_name, facts} <- Enum.sort_by(@groups, &elem(&1, 0))} class="mb-8">
        <h3 class="text-base font-medium border-b pb-1 mb-3">{species_name}</h3>
        <ul class="space-y-2">
          <li
            :for={fact <- facts}
            class="flex items-start justify-between gap-4 rounded-lg border border-gray-200 p-3"
          >
            <div class="min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-xs font-semibold uppercase tracking-wide text-gray-400">
                  {fact_label(fact.fact_key)}{locale_tag(fact.locale)}
                </span>
                <a
                  :if={fact.enrichment_source && fact.enrichment_source.url}
                  href={fact.enrichment_source.url}
                  target="_blank"
                  rel="noopener"
                  class="text-xs text-blue-600 hover:underline"
                >
                  source ↗
                </a>
              </div>
              <p class="text-sm text-gray-800 mt-0.5 break-words">{fact_value(fact)}</p>
            </div>
            <div class="flex shrink-0 gap-2">
              <button
                phx-click="promote"
                phx-value-id={fact.id}
                class="rounded-md bg-green-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-green-700"
              >
                Promote
              </button>
              <button
                phx-click="reject"
                phx-value-id={fact.id}
                class="rounded-md border border-gray-300 px-3 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-50"
              >
                Reject
              </button>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # Color a crosswalk suggestion by match confidence (Jaro distance).
  defp score_class(score) when score >= 0.9, do: "text-green-600 font-medium"
  defp score_class(score) when score >= 0.8, do: "text-amber-600"
  defp score_class(_low), do: "text-gray-400"

  defp status_badge_class("completed"), do: "bg-green-100 text-green-700"
  defp status_badge_class("processing"), do: "bg-amber-100 text-amber-700"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-700"
  defp status_badge_class(_pending), do: "bg-gray-100 text-gray-600"

  defp fact_label("origin_region"), do: "Origin"
  defp fact_label("description"), do: "Description"
  defp fact_label("wikipedia_url"), do: "Wikipedia"
  defp fact_label("top_producers"), do: "Top producers"
  defp fact_label(other), do: other

  defp locale_tag(locale) when locale in [nil, ""], do: ""
  defp locale_tag(locale), do: " · #{locale}"

  defp fact_value(%{fact_key: "top_producers", value_json: %{"producers" => producers}})
       when is_list(producers) do
    producers |> Enum.map(& &1["country"]) |> Enum.join(", ")
  end

  defp fact_value(%{value_text: text}), do: text
end
