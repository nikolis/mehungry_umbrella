defmodule MehungryWeb.ProfessionalLive.SeasonalityLive do
  @moduledoc """
  Admin front door of the seasonality app (`apps/mehungry_seasonality`) — see
  `docs/implementation/seasonality.md`. It talks to that app **only** through the
  `MehungrySeasonality` facade.

  Three jobs on one page, per selected country:

    * **Fetch** — "Fetch <country>" fans out one job per mapped species on the
      `:seasonality` queue and this view watches the batch finish live (rows streamed +
      patched from PubSub, the `processing` signal coalesced behind a flush timer — the
      `oban_ui_connected_worker.md` pattern).
    * **Mappings** — the species ↔ external-product crosswalk (an agri-food portal
      product for the local signal, Comext HS/CN codes for the import signal).
    * **Results** — a species × 12-month grid of the two independent facts (locally on
      the market · imported), with the raw numbers on hover and a per-month override.
  """
  use MehungryWeb, :live_view

  @flush_ms 400
  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Mehungry.PubSub, MehungrySeasonality.runs_topic())

    socket =
      socket
      |> assign(:page_title, "Seasonality")
      |> assign(:countries, MehungrySeasonality.supported_countries())
      |> assign(:species, MehungrySeasonality.list_species())
      |> assign(:fetching?, false)
      |> assign(:processing_ids, MapSet.new())
      |> assign(:flush_scheduled?, false)
      |> assign(:suggestions, %{})
      |> assign(:editing, nil)
      |> assign(:available, :loading)
      |> load_mappings()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    codes = Enum.map(socket.assigns.countries, & &1.code)
    country = if params["country"] in codes, do: params["country"], else: List.first(codes)
    batch_id = country && MehungrySeasonality.latest_batch_id(country)

    {:noreply,
     socket
     |> assign(:country, country)
     |> assign(:editing, nil)
     |> reload_batch(batch_id)
     |> load_grid()
     |> load_available()}
  end

  # The portal's catalogue for the country is two HTTP calls — load it off the
  # render path (and only once connected), so a slow portal never blocks the page.
  defp load_available(%{assigns: %{country: nil}} = socket), do: assign(socket, :available, [])

  defp load_available(socket) do
    country = socket.assigns.country

    if connected?(socket) do
      socket
      |> assign(:available, :loading)
      |> start_async(:available, fn ->
        {country, MehungrySeasonality.available_products(country)}
      end)
    else
      assign(socket, :available, :loading)
    end
  end

  # Catalogue products no species is mapped to yet, most-quoted first — the ones with
  # the most months of local data are the most worth creating a species for.
  defp unmapped_available(available, mapped) when is_list(available) do
    taken =
      for sp <- mapped,
          m <- sp.mappings,
          m.source == "agridata",
          into: MapSet.new(),
          do: m.external_code

    available
    |> Enum.reject(&MapSet.member?(taken, &1.product))
    |> Enum.sort_by(&{-&1.months_quoted, &1.product})
  end

  defp unmapped_available(_not_loaded, _mapped), do: []

  defp load_mappings(socket) do
    mappings = MehungrySeasonality.list_mappings()
    names = Map.new(socket.assigns.species, &{&1.id, species_label(&1)})

    by_species =
      mappings
      |> Enum.group_by(& &1.foundemental_species_id)
      |> Enum.map(fn {species_id, list} ->
        %{
          id: species_id,
          name: Map.get(names, species_id, "Species ##{species_id}"),
          mappings: list
        }
      end)
      |> Enum.sort_by(& &1.name)

    socket
    |> assign(:species_names, names)
    |> assign(:mapped, by_species)
  end

  defp load_grid(%{assigns: %{country: nil}} = socket), do: assign(socket, :grid, [])

  defp load_grid(socket),
    do: assign(socket, :grid, MehungrySeasonality.grid(socket.assigns.country))

  # ── Events: fetch ────────────────────────────────────────────────────────────

  @impl true
  def handle_event("fetch", _params, socket) do
    country = socket.assigns.country

    {:noreply,
     socket
     |> assign(:fetching?, true)
     |> start_async(:fetch, fn -> MehungrySeasonality.fetch_country(country) end)}
  end

  def handle_event("cancel", _params, socket) do
    MehungrySeasonality.cancel_batch(socket.assigns.batch_id)

    {:noreply,
     socket
     |> put_flash(:info, "Batch cancelled — already-fetched data is kept")
     |> reload_batch(socket.assigns.batch_id)}
  end

  # ── Events: mappings ─────────────────────────────────────────────────────────

  def handle_event("add_mapping", %{"mapping" => params}, socket) do
    attrs = %{
      foundemental_species_id: params["species_id"],
      source: params["source"],
      external_code: params["external_code"]
    }

    case MehungrySeasonality.save_mapping(attrs) do
      {:ok, _mapping} ->
        {:noreply, socket |> put_flash(:info, "Mapping added") |> load_mappings() |> load_grid()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add mapping — #{error_text(changeset)}")}
    end
  end

  def handle_event("delete_mapping", %{"id" => id}, socket) do
    MehungrySeasonality.delete_mapping(String.to_integer(id))
    {:noreply, socket |> load_mappings() |> load_grid()}
  end

  def handle_event("reload_available", _params, socket), do: {:noreply, load_available(socket)}

  def handle_event("map_product", %{"product" => product, "species_id" => species_id}, socket) do
    attrs = %{foundemental_species_id: species_id, source: "agridata", external_code: product}

    case MehungrySeasonality.save_mapping(attrs) do
      {:ok, _mapping} ->
        {:noreply,
         socket |> put_flash(:info, "#{product} mapped") |> load_mappings() |> load_grid()}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not map #{product} — #{error_text(changeset)}")}
    end
  end

  def handle_event("suggest", _params, socket) do
    case MehungrySeasonality.suggest_mappings() do
      {:ok, suggestions} when map_size(suggestions) == 0 ->
        {:noreply,
         socket
         |> assign(:suggestions, %{})
         |> put_flash(:info, "No new product matches for the unmapped species")}

      {:ok, suggestions} ->
        {:noreply, assign(socket, :suggestions, suggestions)}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "The agri-food portal product list is unreachable — try again")}
    end
  end

  def handle_event("apply_suggestion", %{"species-id" => id}, socket) do
    species_id = String.to_integer(id)

    case Map.get(socket.assigns.suggestions, species_id) do
      nil ->
        {:noreply, socket}

      %{product: product} ->
        MehungrySeasonality.save_mapping(%{
          foundemental_species_id: species_id,
          source: "agridata",
          external_code: product
        })

        {:noreply,
         socket
         |> update(:suggestions, &Map.delete(&1, species_id))
         |> load_mappings()
         |> load_grid()}
    end
  end

  # ── Events: results ──────────────────────────────────────────────────────────

  def handle_event("edit_cell", %{"species-id" => id, "month" => month}, socket) do
    species_id = String.to_integer(id)
    month = String.to_integer(month)

    case Enum.find(socket.assigns.grid, &(&1.species.id == species_id)) do
      nil ->
        {:noreply, socket}

      row ->
        {:noreply,
         assign(socket, :editing, %{species: row.species, month: month, cell: row.months[month]})}
    end
  end

  def handle_event("close_edit", _params, socket), do: {:noreply, assign(socket, :editing, nil)}

  def handle_event("save_override", %{"override" => params}, socket) do
    case MehungrySeasonality.override_status(editing_key(socket), params) do
      {:ok, _status} ->
        {:noreply,
         socket |> assign(:editing, nil) |> put_flash(:info, "Month updated") |> load_grid()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save — #{error_text(changeset)}")}
    end
  end

  def handle_event("clear_override", _params, socket) do
    MehungrySeasonality.clear_override(editing_key(socket))

    {:noreply,
     socket |> assign(:editing, nil) |> put_flash(:info, "Override cleared") |> load_grid()}
  end

  defp editing_key(%{assigns: %{editing: editing, country: country}}) do
    %{species_id: editing.species.id, country: country, month: editing.month}
  end

  # ── Async results ────────────────────────────────────────────────────────────

  @impl true
  def handle_async(:fetch, {:ok, {:ok, batch_id}}, socket) do
    {:noreply,
     socket
     |> assign(:fetching?, false)
     |> put_flash(:info, "Fetch started — watch each species finish below")
     |> reload_batch(batch_id)}
  end

  def handle_async(:fetch, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:fetching?, false) |> put_flash(:error, fetch_error(reason))}
  end

  def handle_async(:fetch, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:fetching?, false)
     |> put_flash(:error, "Could not start the fetch — #{inspect(reason)}")}
  end

  # Ignore a catalogue that arrives after the admin switched country.
  def handle_async(:available, {:ok, {country, result}}, socket) do
    cond do
      country != socket.assigns.country -> {:noreply, socket}
      match?({:ok, _}, result) -> {:noreply, assign(socket, :available, elem(result, 1))}
      true -> {:noreply, assign(socket, :available, :error)}
    end
  end

  def handle_async(:available, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, :available, :error)}

  defp fetch_error(:no_mappings), do: "Map at least one species to a product first"
  defp fetch_error(:already_running), do: "A fetch for this country is already running"
  defp fetch_error(:unsupported_country), do: "This country is not enabled"

  # ── Live progress ────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:seasonality_run, run}, socket) do
    if run.batch_id == socket.assigns.batch_id do
      {:noreply,
       socket
       |> stream_insert(:rows, run)
       |> assign(:counts, MehungrySeasonality.counts_for_batch(run.batch_id))
       # A finished species has fresh statuses — refresh the grid.
       |> load_grid()}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:seasonality_processing, batch_id, species_id}, socket) do
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
      MehungrySeasonality.list_batch_rows(socket.assigns.batch_id)
      |> Enum.filter(&(&1.foundemental_species_id in ids))
      |> Enum.reduce(socket, fn row, acc -> stream_insert(acc, :rows, row) end)

    {:noreply,
     assign(socket, :counts, MehungrySeasonality.counts_for_batch(socket.assigns.batch_id))}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp reload_batch(socket, batch_id) do
    socket
    |> assign(:batch_id, batch_id)
    |> assign(:counts, MehungrySeasonality.counts_for_batch(batch_id))
    |> stream(:rows, MehungrySeasonality.list_batch_rows(batch_id), reset: true)
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

  defp species_label(%{name: name, variety: variety}) when variety not in [nil, ""],
    do: "#{name} (#{variety})"

  defp species_label(%{name: name}), do: name

  defp error_text(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp country_name(code), do: MehungrySeasonality.country_name(code)

  # ── View ─────────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :months, @months)

    ~H"""
    <div class="max-w-6xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-semibold mb-1">Seasonality</h1>
      <p class="text-sm text-gray-500 mb-4">
        Per food species and month: is it locally on the market, and is it imported — two
        independent facts. Local comes from producer price quotes on the EU agri-food data
        portal, imports from Eurostat Comext monthly trade (CC BY 4.0), averaged over the
        last three complete years.
      </p>

      <p :if={@countries == []} class="rounded-md bg-amber-50 text-amber-800 px-3 py-2 text-sm">
        No country is enabled — set <code>config :mehungry_seasonality, countries: [...]</code>.
      </p>

      <nav :if={@countries != []} class="flex flex-wrap gap-2 mb-6" aria-label="Country">
        <.link
          :for={c <- @countries}
          patch={~p"/professional/seasonality?country=#{c.code}"}
          class={[
            "rounded-md px-3 py-1.5 text-sm border",
            if(c.code == @country,
              do: "bg-gray-800 text-white border-gray-800",
              else: "bg-white text-gray-700 border-gray-300 hover:bg-gray-50"
            )
          ]}
        >
          {c.name}
        </.link>
      </nav>

      <div :if={@country}>
        <%!-- ── Fetch trigger + live progress ────────────────────────────────── --%>
        <section class="rounded-lg border border-gray-200 bg-gray-50 p-4 mb-8">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="text-sm text-gray-600">
              One job per mapped species on the <code>:seasonality</code>
              queue — watch each finish below.
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
                phx-click="fetch"
                disabled={@fetching? or in_flight?(@counts)}
                class="rounded-md bg-green-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-40 disabled:cursor-not-allowed"
              >
                {if @fetching? or in_flight?(@counts),
                  do: "Fetching…",
                  else: "Fetch #{country_name(@country)}"}
              </button>
            </div>
          </div>

          <div class="mt-3 flex flex-wrap gap-4 text-sm">
            <span class="text-gray-500">Pending
            <span class="text-gray-800 font-medium">{@counts.pending}</span></span>
            <span class="text-gray-500">Processing
            <span class="text-amber-600 font-medium">{@counts.processing}</span></span>
            <span class="text-gray-500">Completed
            <span class="text-green-700 font-medium">{@counts.completed}</span></span>
            <span class="text-gray-500">Failed
            <span class="text-red-600 font-medium">{@counts.failed}</span></span>
          </div>

          <div id="seasonality-rows" phx-update="stream" class="mt-3 divide-y divide-gray-200">
            <div
              :for={{dom_id, row} <- @streams.rows}
              id={dom_id}
              class="flex flex-wrap items-center gap-3 py-2 text-sm"
            >
              <span class="min-w-[12rem] text-gray-800">{species_label(row.species)}</span>
              <span class={"inline-flex rounded-full px-2 py-0.5 text-xs font-medium #{status_badge_class(row.status)}"}>
                {row.status}
              </span>
              <span :if={row.status == "completed"} class="text-xs text-gray-500">
                {row.local_count} local · {row.import_count} import months
              </span>
              <span
                :if={row.status == "failed" and row.error}
                class="text-xs text-red-600 truncate max-w-[24rem]"
                title={row.error}
              >
                {row.error}
              </span>
            </div>
          </div>

          <p :if={@counts.total == 0} class="mt-3 text-sm text-gray-500">
            No fetch yet for {country_name(@country)}.
          </p>
        </section>

        <%!-- ── Results grid ─────────────────────────────────────────────────── --%>
        <section class="rounded-lg border border-gray-200 bg-white p-4 mb-8">
          <div class="flex flex-wrap items-baseline justify-between gap-3 mb-3">
            <h2 class="text-lg font-semibold">Results — {country_name(@country)}</h2>
            <.legend />
          </div>

          <p :if={@grid == []} class="text-sm text-gray-500">
            Nothing to show — map a species below, then fetch.
          </p>

          <div :if={@grid != []} class="overflow-x-auto">
            <table
              id="seasonality-grid"
              class="w-full text-sm border-separate border-spacing-x-0.5 border-spacing-y-1"
            >
              <thead>
                <tr class="text-xs text-gray-500">
                  <th class="text-left font-medium pr-3 min-w-[10rem]">Species</th>
                  <th :for={label <- @months} class="font-medium w-12">{label}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @grid} id={"grid-species-#{row.species.id}"}>
                  <td class="pr-3 text-gray-800 whitespace-nowrap">{species_label(row.species)}</td>
                  <td :for={month <- 1..12} class="p-0">
                    <button
                      type="button"
                      id={"cell-#{row.species.id}-#{month}"}
                      phx-click="edit_cell"
                      phx-value-species-id={row.species.id}
                      phx-value-month={month}
                      title={cell_title(row.months[month], Enum.at(@months, month - 1))}
                      data-local={cell_local(row.months[month])}
                      data-imported={cell_imported(row.months[month])}
                      class="relative block w-full h-9 rounded overflow-hidden ring-1 ring-gray-200 hover:ring-2 hover:ring-gray-500"
                    >
                      <span class={"block h-6 #{local_class(cell_local(row.months[month]))}"}></span>
                      <span class={"block h-3 #{imported_class(cell_imported(row.months[month]))}"}></span>
                      <span
                        :if={curated?(row.months[month])}
                        class="absolute top-0.5 right-0.5 h-1.5 w-1.5 rounded-full bg-gray-900"
                        aria-label="hand-set"
                      ></span>
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <p :if={@grid != []} class="mt-3 text-xs text-gray-500">
            Hover a month for the numbers behind it; click to set it by hand. Sources: EU agri-food
            data portal (European Commission) · Eurostat Comext (CC BY 4.0).
          </p>
        </section>

        <%!-- ── Available but unmapped ───────────────────────────────────────── --%>
        <section
          id="seasonality-available"
          class="rounded-lg border border-gray-200 bg-white p-4 mb-8"
        >
          <h2 class="text-lg font-semibold mb-1">
            Available foods without a mapping — {country_name(@country)}
          </h2>
          <p class="text-sm text-gray-500 mb-4">
            Every food the EU agri-food portal has producer price data for in {country_name(@country)} last year that no species is mapped to yet, most data first. Map it to an existing
            species here, or create the missing species in the
            <.link href="/professional/usda-schema" class="text-blue-700 underline">USDA schema</.link>
            first.
          </p>

          <p :if={@available == :loading} class="text-sm text-gray-500">
            Loading the portal catalogue…
          </p>

          <p :if={@available == :error} class="text-sm text-red-600">
            The agri-food portal is unreachable.
            <button phx-click="reload_available" class="underline">Try again</button>
          </p>

          <p
            :if={is_list(@available) and unmapped_available(@available, @mapped) == []}
            class="text-sm text-gray-500"
          >
            Nothing left — every available food is mapped.
          </p>

          <ul :if={is_list(@available)} class="divide-y divide-gray-200">
            <li
              :for={item <- unmapped_available(@available, @mapped)}
              id={"available-#{String.replace(item.product, ~r/[^A-Za-z0-9]+/, "-")}"}
              class="flex flex-wrap items-center gap-x-4 gap-y-2 py-2.5 text-sm"
            >
              <span class="min-w-[12rem] text-gray-800 font-medium">{item.product}</span>
              <span class="text-xs text-gray-500 min-w-[8rem]">
                quoted in {item.months_quoted} of 12 months
              </span>
              <span
                :if={is_nil(item.suggested_species_id)}
                class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium bg-amber-100 text-amber-700"
              >
                no species yet
              </span>
              <span
                :if={item.suggested_species_id}
                class="inline-flex rounded-full px-2 py-0.5 text-xs font-medium bg-green-100 text-green-700"
              >
                species exists
              </span>
              <form phx-submit="map_product" class="ml-auto flex items-center gap-2">
                <input type="hidden" name="product" value={item.product} />
                <select name="species_id" required class="rounded-md border-gray-300 text-xs py-1">
                  <option value="">Map to species…</option>
                  <option
                    :for={sp <- @species}
                    value={sp.id}
                    selected={sp.id == item.suggested_species_id}
                  >
                    {species_label(sp)}
                  </option>
                </select>
                <button class="rounded-md border border-gray-300 bg-white px-2.5 py-1 text-xs hover:bg-gray-50">
                  Map
                </button>
              </form>
            </li>
          </ul>
        </section>

        <%!-- ── Mappings ─────────────────────────────────────────────────────── --%>
        <section class="rounded-lg border border-gray-200 bg-gray-50 p-4 mb-8">
          <div class="flex flex-wrap items-center justify-between gap-3 mb-1">
            <h2 class="text-lg font-semibold">Species mappings</h2>
            <div class="flex items-center gap-3 text-sm">
              <span class="text-gray-500">{length(@mapped)} / {length(@species)} species mapped</span>
              <button
                phx-click="suggest"
                class="rounded-md bg-blue-600 px-3 py-1.5 font-medium text-white hover:bg-blue-700"
              >
                Run suggester
              </button>
            </div>
          </div>
          <p class="text-sm text-gray-500 mb-4">
            A species is fetched only when mapped. <span class="font-medium">Local</span>
            needs an agri-food portal product (the suggester fuzzy-matches species names to it — a
            hint, confirm it). <span class="font-medium">Imports</span>
            need an HS/CN product code, e.g. <code>0702</code>
            for tomatoes or <code>080930</code>
            for peaches. Mappings apply to every country.
          </p>

          <ul
            :if={map_size(@suggestions) > 0}
            id="seasonality-suggestions"
            class="mb-4 divide-y divide-blue-100 rounded-md bg-blue-50 px-3"
          >
            <li
              :for={
                {species_id, suggestion} <-
                  Enum.sort_by(@suggestions, fn {id, _} -> @species_names[id] end)
              }
              class="flex flex-wrap items-center gap-3 py-2 text-sm"
            >
              <span class="min-w-[12rem] text-gray-800">{@species_names[species_id]}</span>
              <span class="text-gray-600">→ {suggestion.product}</span>
              <span class={"text-xs #{score_class(suggestion.score)}"}>{suggestion.score}</span>
              <button
                phx-click="apply_suggestion"
                phx-value-species-id={species_id}
                class="ml-auto rounded-md border border-gray-300 bg-white px-2.5 py-1 text-xs hover:bg-gray-50"
              >
                Apply
              </button>
            </li>
          </ul>

          <form
            id="add-mapping-form"
            phx-submit="add_mapping"
            class="flex flex-wrap items-end gap-3 mb-4"
          >
            <label class="text-xs text-gray-600">
              Species
              <select
                name="mapping[species_id]"
                required
                class="mt-1 block rounded-md border-gray-300 text-sm min-w-[14rem]"
              >
                <option value="">Choose…</option>
                <option :for={sp <- @species} value={sp.id}>{species_label(sp)}</option>
              </select>
            </label>
            <label class="text-xs text-gray-600">
              Signal
              <select name="mapping[source]" class="mt-1 block rounded-md border-gray-300 text-sm">
                <option value="agridata">Local — agri-food product</option>
                <option value="comext">Imports — HS/CN code</option>
              </select>
            </label>
            <label class="text-xs text-gray-600">
              Product name or code
              <input
                type="text"
                name="mapping[external_code]"
                required
                placeholder="Tomatoes / 0702"
                class="mt-1 block rounded-md border-gray-300 text-sm"
              />
            </label>
            <button class="rounded-md bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700">
              Add mapping
            </button>
          </form>

          <ul id="seasonality-mappings" class="divide-y divide-gray-200">
            <li
              :for={sp <- @mapped}
              class="flex flex-wrap items-center gap-x-4 gap-y-2 py-2.5 text-sm"
            >
              <span class="min-w-[12rem] text-gray-800">{sp.name}</span>
              <span
                :for={m <- sp.mappings}
                class="inline-flex items-center gap-1.5 rounded-full bg-white border border-gray-300 pl-2.5 pr-1 py-0.5 text-xs"
              >
                <span class="text-gray-500">{source_label(m.source)}</span>
                <span class="text-gray-800 font-medium">{m.external_code}</span>
                <button
                  phx-click="delete_mapping"
                  phx-value-id={m.id}
                  data-confirm={"Remove the #{m.external_code} mapping?"}
                  aria-label={"Remove #{m.external_code}"}
                  class="rounded-full px-1.5 text-gray-400 hover:bg-red-50 hover:text-red-600"
                >
                  ×
                </button>
              </span>
            </li>
          </ul>
          <p :if={@mapped == []} class="text-sm text-gray-500">No species mapped yet.</p>
        </section>
      </div>

      <.modal :if={@editing} id="seasonality-edit" show on_cancel={JS.push("close_edit")}>
        <h2 class="text-lg font-semibold mb-1">
          {species_label(@editing.species)} — {Enum.at(@months, @editing.month - 1)} · {country_name(
            @country
          )}
        </h2>
        <p class="text-sm text-parchment-dim mb-4">{cell_title(@editing.cell, nil)}</p>

        <form id="override-form" phx-submit="save_override" class="space-y-4">
          <label class="block text-sm">
            Locally on the market
            <select
              name="override[local]"
              class="mt-1 block w-full rounded-md border-gray-300 text-sm text-gray-900"
            >
              <option value="">Derived from data</option>
              <option
                :for={value <- MehungrySeasonality.local_values() -- ["unknown", "unresolved"]}
                value={value}
                selected={curated_value(@editing.cell, :local) == value}
              >
                {status_label(value)}
              </option>
            </select>
          </label>
          <label class="block text-sm">
            Imported
            <select
              name="override[imported]"
              class="mt-1 block w-full rounded-md border-gray-300 text-sm text-gray-900"
            >
              <option value="">Derived from data</option>
              <option
                :for={value <- MehungrySeasonality.imported_values() -- ["unknown"]}
                value={value}
                selected={curated_value(@editing.cell, :imported) == value}
              >
                {status_label(value)}
              </option>
            </select>
          </label>
          <label class="block text-sm">
            Note
            <input
              type="text"
              name="override[note]"
              value={@editing.cell.status && @editing.cell.status.note}
              class="mt-1 block w-full rounded-md border-gray-300 text-sm text-gray-900"
            />
          </label>
          <div class="flex items-center gap-2">
            <button class="rounded-md bg-green-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-green-700">
              Save
            </button>
            <button
              :if={curated?(@editing.cell)}
              type="button"
              phx-click="clear_override"
              class="rounded-md border border-gray-300 bg-white px-3 py-1.5 text-sm text-gray-800 hover:bg-gray-50"
            >
              Clear override
            </button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end

  defp legend(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-gray-600">
      <span class="font-medium text-gray-700">Local</span>
      <span
        :for={value <- ~w(in_season greenhouse stored unresolved none unknown)}
        class="inline-flex items-center gap-1"
      >
        <span class={"inline-block h-3 w-4 rounded-sm ring-1 ring-gray-200 #{local_class(value)}"}></span>
        {status_label(value)}
      </span>
      <span class="font-medium text-gray-700 ml-2">Imported</span>
      <span :for={value <- ~w(major some none)} class="inline-flex items-center gap-1">
        <span class={"inline-block h-2 w-4 rounded-sm ring-1 ring-gray-200 #{imported_class(value)}"}></span>
        {status_label(value)}
      </span>
      <span class="inline-flex items-center gap-1">
        <span class="inline-block h-1.5 w-1.5 rounded-full bg-gray-900"></span> hand-set
      </span>
    </div>
    """
  end

  # ── Cell helpers ─────────────────────────────────────────────────────────────

  defp cell_local(%{status: %{local: local}}), do: local
  defp cell_local(_), do: "unknown"

  defp cell_imported(%{status: %{imported: imported}}), do: imported
  defp cell_imported(_), do: "unknown"

  defp curated?(%{status: %{local_curated: local, imported_curated: imported}}),
    do: local or imported

  defp curated?(_), do: false

  defp curated_value(%{status: %{local_curated: true, local: value}}, :local), do: value
  defp curated_value(%{status: %{imported_curated: true, imported: value}}, :imported), do: value
  defp curated_value(_cell, _field), do: nil

  defp local_class("in_season"), do: "bg-green-500"
  defp local_class("greenhouse"), do: "bg-teal-400"
  defp local_class("stored"), do: "bg-amber-400"
  defp local_class("unresolved"), do: "bg-yellow-200"
  defp local_class("none"), do: "bg-gray-100"
  defp local_class(_unknown), do: "bg-white"

  defp imported_class("major"), do: "bg-blue-600"
  defp imported_class("some"), do: "bg-blue-300"
  defp imported_class("none"), do: "bg-gray-100"
  defp imported_class(_unknown), do: "bg-white"

  defp status_label("in_season"), do: "In season"
  defp status_label("greenhouse"), do: "Greenhouse"
  defp status_label("stored"), do: "Stored"
  defp status_label("unresolved"), do: "All year (unresolved)"
  defp status_label("none"), do: "None"
  defp status_label("some"), do: "Some"
  defp status_label("major"), do: "Major"
  defp status_label(_unknown), do: "No source"

  defp source_label("agridata"), do: "local"
  defp source_label("comext"), do: "imports"
  defp source_label(other), do: other

  # The numbers behind a cell, as a tooltip / modal subtitle.
  defp cell_title(cell, month_label) do
    [
      month_label,
      "Local: #{status_label(cell_local(cell))}#{local_detail(cell)}",
      "Imported: #{status_label(cell_imported(cell))}#{import_detail(cell)}",
      cell[:status] && cell.status.note
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp local_detail(%{local: %{weeks_quoted: quoted, weeks_possible: possible}})
       when possible > 0,
       do: " (quoted #{quoted} of #{possible} weeks)"

  defp local_detail(_), do: ""

  defp import_detail(%{import: %{tonnes_avg: tonnes, origins: origins}}) when tonnes > 0 do
    from =
      case origins do
        [] ->
          ""

        list ->
          ", from " <> Enum.map_join(list, ", ", &"#{&1["country"]} #{round(&1["share"] * 100)}%")
      end

    " (#{format_tonnes(tonnes)} t/month#{from})"
  end

  defp import_detail(_), do: ""

  defp format_tonnes(tonnes) when tonnes >= 100, do: tonnes |> round() |> Integer.to_string()
  defp format_tonnes(tonnes), do: :erlang.float_to_binary(tonnes * 1.0, decimals: 1)

  defp status_badge_class("completed"), do: "bg-green-100 text-green-700"
  defp status_badge_class("processing"), do: "bg-amber-100 text-amber-700"
  defp status_badge_class("failed"), do: "bg-red-100 text-red-700"
  defp status_badge_class(_), do: "bg-gray-100 text-gray-600"

  defp score_class(score) when score >= 0.95, do: "text-green-700"
  defp score_class(_score), do: "text-amber-700"
end
