defmodule MehungryWeb.ProfessionalLive.FactMiningPipeline do
  @moduledoc """
  The admin front door for `Mehungry.FactMining` — the pipeline that mines
  per-species biomedical facts from the external **biomed-fact-miner** (`POST /mine`)
  and stores them as `SpeciesMinedFact` rows (replacing the old species↔compound
  derivation).

  **One species at a time, with an editable prompt.** The admin picks a species and
  edits the question sent to the miner (pre-filled with the default
  `FactMining.query_for_species/1`); submitting enqueues a single
  `SpeciesFactMiningWorker` job (a one-row batch) on the serialized `:fact_mining`
  queue. The view watches it finish live — a stream of per-species tracking rows
  patched O(1) from PubSub, with the high-frequency `processing` signal coalesced
  behind a flush timer (the `oban_ui_connected_worker.md` pattern). The bulk
  "Mine all species" fan-out (`Runs.mine_all_species/0`) is kept dormant (no UI).
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.FactMining
  alias Mehungry.FactMining.Settings
  alias Mehungry.FactMining.SpeciesFactMiningRuns, as: Runs

  @flush_ms 400

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, Runs.topic())
    end

    batch_id = Runs.latest_batch_id()

    species = Food.list_foundemental_species()

    socket =
      socket
      |> assign(:page_title, "Fact mining")
      |> assign(:batch_id, batch_id)
      |> assign(:counts, Runs.counts_for_batch(batch_id))
      |> assign(:reachable, :unknown)
      |> assign(:mining?, false)
      |> assign(:species_options, species)
      |> assign(:selected_species_id, nil)
      |> assign(:mine_query, "")
      |> assign(:processing_ids, MapSet.new())
      |> assign(:flush_scheduled?, false)
      |> assign_settings_form()
      |> stream(:rows, Runs.list_batch_rows(batch_id))

    socket =
      if connected?(socket),
        do: start_async(socket, :reachable, fn -> FactMining.reachable?() end),
        else: socket

    {:ok, socket}
  end

  # Build the connection form from the saved settings row (or a blank one seeded
  # with the currently-resolved base URL so the admin sees the effective default).
  defp assign_settings_form(socket) do
    settings = FactMining.get_settings() || %Settings{base_url: FactMining.base_url()}

    socket
    |> assign(:settings, settings)
    |> assign(:settings_form, to_form(Settings.changeset(settings, %{})))
  end

  # ── Triggers ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("select_species", %{"species_id" => id}, socket) do
    # Only fired by the <select> → refill the prompt with the chosen species'
    # default (typing in the textarea doesn't fire this, so edits survive).
    {species_id, species} = resolve_species(socket, id)

    query = if species, do: FactMining.query_for_species(species), else: ""

    {:noreply,
     socket
     |> assign(:selected_species_id, species_id)
     |> assign(:mine_query, query)}
  end

  @impl true
  def handle_event("mine_species", %{"species_id" => id, "query" => query}, socket) do
    case Integer.parse(to_string(id)) do
      {species_id, _} ->
        {:noreply,
         socket
         |> assign(:mining?, true)
         |> assign(:selected_species_id, species_id)
         |> assign(:mine_query, query)
         |> start_async(:mine_one, fn -> Runs.mine_species(species_id, query) end)}

      :error ->
        {:noreply, put_flash(socket, :error, "Pick a species to mine")}
    end
  end

  @impl true
  def handle_event("cancel", _params, socket) do
    Runs.cancel_batch(socket.assigns.batch_id)
    {:noreply, reload_batch(socket, socket.assigns.batch_id)}
  end

  @impl true
  def handle_event("recheck", _params, socket) do
    {:noreply,
     socket
     |> assign(:reachable, :unknown)
     |> start_async(:reachable, fn -> FactMining.reachable?() end)}
  end

  @impl true
  def handle_event("validate_connection", %{"settings" => params}, socket) do
    changeset = Settings.changeset(socket.assigns.settings, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :settings_form, to_form(changeset))}
  end

  @impl true
  def handle_event("save_connection", %{"settings" => params}, socket) do
    case FactMining.update_settings(params) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> assign_settings_form()
         |> assign(:reachable, :unknown)
         |> start_async(:reachable, fn -> FactMining.reachable?() end)
         |> put_flash(:info, "Miner connection saved — re-checking…")}

      {:error, changeset} ->
        {:noreply, assign(socket, :settings_form, to_form(changeset))}
    end
  end

  # ── Async results ────────────────────────────────────────────────────────────

  @impl true
  def handle_async(:reachable, {:ok, result}, socket) do
    {:noreply, assign(socket, :reachable, result)}
  end

  def handle_async(:reachable, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :reachable, {:error, :probe_crashed})}
  end

  def handle_async(:mine_one, {:ok, {:ok, batch_id}}, socket) do
    {:noreply,
     socket
     |> assign(:mining?, false)
     |> put_flash(:info, "Mining started — watch the species finish below")
     |> reload_batch(batch_id)}
  end

  def handle_async(:mine_one, {:ok, {:error, {:already_running, _species_id}}}, socket) do
    {:noreply,
     socket
     |> assign(:mining?, false)
     |> put_flash(
       :error,
       "This species already has a mine in the queue — wait for it to finish or cancel it first."
     )}
  end

  def handle_async(:mine_one, {:ok, {:error, {:unreachable, reason}}}, socket) do
    {:noreply,
     socket
     |> assign(:mining?, false)
     |> assign(:reachable, {:error, reason})
     |> put_flash(:error, "Fact miner unreachable — #{inspect(reason)}")}
  end

  def handle_async(:mine_one, {:ok, {:error, :not_found}}, socket) do
    {:noreply,
     socket
     |> assign(:mining?, false)
     |> put_flash(:error, "That species no longer exists")}
  end

  def handle_async(:mine_one, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:mining?, false)
     |> put_flash(:error, "Could not start mining — #{inspect(reason)}")}
  end

  # ── Live progress ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:fact_mining_run, run}, socket) do
    if run.batch_id == socket.assigns.batch_id do
      {:noreply,
       socket
       |> stream_insert(:rows, run)
       |> assign(:counts, Runs.counts_for_batch(socket.assigns.batch_id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:fact_mining_processing, batch_id, species_id}, socket) do
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

  # Resolve the picked `species_id` (a form string) to `{integer_id | nil, species | nil}`
  # from the already-loaded options (no extra query).
  defp resolve_species(socket, id) do
    case Integer.parse(to_string(id)) do
      {species_id, _} ->
        species = Enum.find(socket.assigns.species_options, &(&1.id == species_id))
        {species_id, species}

      :error ->
        {nil, nil}
    end
  end

  defp buffer_processing(socket, species_id) do
    update(socket, :processing_ids, &MapSet.put(&1, species_id))
  end

  defp maybe_schedule_flush(socket) do
    if socket.assigns.flush_scheduled? do
      socket
    else
      Process.send_after(self(), :flush_processing, @flush_ms)
      assign(socket, :flush_scheduled?, true)
    end
  end

  # ── View helpers (used by the template) ──────────────────────────────────────

  @doc false
  def in_flight?(counts), do: counts.pending + counts.processing > 0

  @doc false
  def status_badge_class("completed"), do: "bg-basil/20 text-basil"
  def status_badge_class("processing"), do: "bg-amber-500/20 text-amber-300"
  def status_badge_class("failed"), do: "bg-paprika/20 text-paprika"
  def status_badge_class(_pending), do: "bg-ink-panel2 text-parchment-dim"
end
