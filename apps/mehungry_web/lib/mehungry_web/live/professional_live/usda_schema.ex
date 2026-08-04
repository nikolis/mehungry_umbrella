defmodule MehungryWeb.ProfessionalLive.UsdaSchema do
  @moduledoc """
  Admin read-only view over `Mehungry.FoodData.Usda.SchemaMatcher`: the app's
  fdc-backed ingredients grouped by the structural *schema* of their USDA
  description (the parser's field signature), against a catalog of schemas
  inherited from the reference USDA datasets. Each schema is an accordion —
  header shows the dimension pattern and match count, expanding reveals the
  matched ingredients. Ingredients that match no schema exactly are collected in
  a trailing "Unmatched" panel.

  On top of the read-only view sits a **curation** step: each matched ingredient
  carries a species select that maps it onto a `Food.FoundementalFoodSpecies`
  (creating a `Food.FoundementalFood` join row), with a "+ New species…" option
  that opens a modal to define the species inline. Once curated, an ingredient
  drops out of the schema/unmatched lists and reappears in a second accordion
  grouped under its species.

  ## Performance

  The biggest schemas hold >1k ingredients, so the matched-row lists must never
  be re-rendered wholesale. Two measures keep the page responsive:

    * only **one** schema/unmatched panel is open at a time, and its rows are a
      LiveView **stream** (`:rows`) — assigning an ingredient is a single
      `stream_delete` (one-row diff), not a re-render of the whole panel;
    * the panel renders at most `@page` rows up front, revealing more on demand.

  The heavy corpus parse runs off the mount critical path (async `:load`) and on
  explicit "Recompute" only; assigning an ingredient never re-parses — it patches
  the in-memory lists and the small curation tables.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.FoundementalFoodSpecies
  alias Mehungry.FoodData.Usda.SchemaMatcher

  # Rows rendered per panel before "Show more".
  @page 100

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "USDA Schema")
      |> assign(:expanded, MapSet.new())
      |> assign(:show_species_modal, false)
      |> assign(:show_assign_modal, false)
      |> assign(:pending_assignment, nil)
      |> assign(:species_form, new_species_form())
      |> assign(:loading, true)
      |> assign(:active_key, nil)
      |> assign(:active_rows, [])
      |> assign(:row_limit, @page)
      |> assign_empty_analysis()
      |> stream(:rows, [])

    # The heavy corpus parse must not block the mount (it runs the full USDA
    # parser over every ingredient). Skip it on the dead render entirely, and on
    # the connected socket kick it off in a follow-up message so the page paints
    # a "Computing…" state immediately instead of freezing.
    if connected?(socket), do: send(self(), :load)

    {:ok, socket}
  end

  @impl true
  def handle_info(:load, socket) do
    {:noreply, socket |> load() |> assign(:loading, false)}
  end

  @impl true
  def handle_event("recompute", _params, socket) do
    {:noreply,
     socket
     |> load()
     |> put_flash(:info, "Recomputed from current ingredients")}
  end

  # Species-foods accordions (bottom section) — small, plain expand/collapse.
  @impl true
  def handle_event("toggle", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, key),
        do: MapSet.delete(expanded, key),
        else: MapSet.put(expanded, key)

    {:noreply, assign(socket, :expanded, expanded)}
  end

  # Schema / unmatched panels — single-active, streamed rows. Re-clicking the
  # open panel collapses it.
  def handle_event("open_panel", %{"key" => key}, socket) do
    if socket.assigns.active_key == key do
      {:noreply, collapse_panel(socket)}
    else
      rows = rows_for(socket.assigns, key)

      {:noreply,
       socket
       |> assign(:active_key, key)
       |> assign(:active_rows, rows)
       |> assign(:row_limit, @page)
       |> stream(:rows, Enum.take(rows, @page), reset: true)}
    end
  end

  def handle_event("load_more", _params, socket) do
    %{active_rows: rows, row_limit: limit} = socket.assigns

    socket =
      rows
      |> Enum.slice(limit, @page)
      |> Enum.reduce(socket, fn row, acc -> stream_insert(acc, :rows, row) end)

    {:noreply, assign(socket, :row_limit, limit + @page)}
  end

  # Blank selection ("— assign species —") is a no-op.
  def handle_event("select_species", %{"species_id" => ""}, socket), do: {:noreply, socket}

  # "+ New species…" — stash which ingredient is being classified and open the
  # modal; the created species is assigned to it on submit.
  def handle_event(
        "select_species",
        %{"species_id" => "__new__", "ingredient_id" => ingredient_id, "usda_name" => usda_name},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:pending_assignment, %{
       ingredient_id: String.to_integer(ingredient_id),
       usda_name: usda_name
     })
     |> assign(:species_form, new_species_form())
     |> assign(:show_species_modal, true)}
  end

  # Existing species — mirror the "+ New species…" flow: stash the pending
  # assignment and open a confirmation modal to submit, skipping species creation.
  def handle_event(
        "select_species",
        %{"species_id" => species_id, "ingredient_id" => ingredient_id, "usda_name" => usda_name},
        socket
      ) do
    species_id = String.to_integer(species_id)
    species = Enum.find(socket.assigns.species, &(&1.id == species_id))

    {:noreply,
     socket
     |> assign(:pending_assignment, %{
       ingredient_id: String.to_integer(ingredient_id),
       usda_name: usda_name,
       species_id: species_id,
       species_label: species && species_label(species)
     })
     |> assign(:show_assign_modal, true)}
  end

  # Submit of the confirmation modal for an existing species.
  def handle_event("confirm_assignment", _params, socket) do
    %{ingredient_id: ingredient_id, usda_name: usda_name, species_id: species_id} =
      socket.assigns.pending_assignment

    socket =
      socket
      |> assign(:show_assign_modal, false)
      |> assign(:pending_assignment, nil)

    case Food.assign_foundemental_ingredient(species_id, ingredient_id, usda_name) do
      {:ok, _} ->
        {:noreply,
         socket
         |> after_assign_data(ingredient_id)
         |> stream_delete(:rows, %{id: ingredient_id})
         |> put_flash(:info, "Assigned to species")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not assign ingredient to species")}
    end
  end

  def handle_event("close_assign_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_assign_modal, false)
     |> assign(:pending_assignment, nil)}
  end

  def handle_event("create_species", %{"foundemental_food_species" => params}, socket) do
    case Food.create_foundemental_species(params) do
      {:ok, species} ->
        pending = socket.assigns.pending_assignment
        maybe_assign_pending(socket, species)

        socket =
          socket
          |> assign(:show_species_modal, false)
          |> assign(:pending_assignment, nil)

        socket =
          case pending do
            %{ingredient_id: ingredient_id} ->
              # New species now exists — re-stream the visible rows so their
              # dropdowns include it, dropping the just-assigned one.
              socket |> after_assign_data(ingredient_id) |> restream_active()

            _ ->
              reload_species(socket)
          end

        {:noreply, put_flash(socket, :info, "Created species \"#{species.name}\"")}

      {:error, changeset} ->
        {:noreply, assign(socket, :species_form, to_form(changeset))}
    end
  end

  def handle_event("close_species_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_species_modal, false)
     |> assign(:pending_assignment, nil)}
  end

  # ── Loading / filtering ──────────────────────────────────────────────────────

  # Heavy: parses the whole corpus (full USDA parser over every ingredient), so
  # it is only ever run off the mount critical path — from the async :load
  # message and explicit Recompute, never on the dead render. Layers the (cheap)
  # curation filter on top and collapses any open panel.
  defp load(socket) do
    analysis = SchemaMatcher.analyze()

    socket
    |> assign(:source, analysis.source)
    |> assign(:raw_schemas, analysis.schemas)
    |> assign(:raw_unmatched, analysis.unmatched)
    |> assign(:total_ingredients, analysis.total_ingredients)
    |> assign(:schema_count, analysis.schema_count)
    |> refresh_curation()
    |> collapse_panel()
  end

  # Safe empty defaults so the template renders during the "Computing…" window
  # before the async :load has populated the real analysis.
  defp assign_empty_analysis(socket) do
    socket
    |> assign(:source, :ingredients)
    |> assign(:raw_schemas, [])
    |> assign(:raw_unmatched, [])
    |> assign(:total_ingredients, 0)
    |> assign(:schema_count, 0)
    |> assign(:schemas, [])
    |> assign(:unmatched, [])
    |> assign(:matched_count, 0)
    |> assign(:unmatched_count, 0)
    |> assign(:species, [])
    |> assign(:species_with_foods, [])
  end

  # Cheap: re-reads the curation tables and drops already-assigned ingredients
  # from the schema/unmatched lists, then rebuilds the species accordion. Called
  # only from load/1 — assignment events patch the lists in place instead.
  defp refresh_curation(socket) do
    assigned = Food.assigned_foundemental_ingredient_ids()

    schemas =
      for schema <- socket.assigns.raw_schemas do
        matched = Enum.reject(schema.matched, &MapSet.member?(assigned, &1.id))
        %{schema | matched: matched, matched_count: length(matched)}
      end

    unmatched =
      Enum.reject(socket.assigns.raw_unmatched, &MapSet.member?(assigned, &1.ingredient.id))

    matched_count = schemas |> Enum.map(& &1.matched_count) |> Enum.sum()

    socket
    |> assign(:schemas, schemas)
    |> assign(:unmatched, unmatched)
    |> assign(:matched_count, matched_count)
    |> assign(:unmatched_count, length(unmatched))
    |> reload_species()
  end

  # ── Curation panel (streamed rows) ────────────────────────────────────────────

  defp collapse_panel(socket) do
    socket
    |> assign(:active_key, nil)
    |> assign(:active_rows, [])
    |> assign(:row_limit, @page)
    |> stream(:rows, [], reset: true)
  end

  defp restream_active(socket) do
    stream(socket, :rows, Enum.take(socket.assigns.active_rows, socket.assigns.row_limit),
      reset: true
    )
  end

  # Normalized, stream-friendly rows (uniform shape + an :id for the dom id).
  defp rows_for(assigns, "__unmatched__"),
    do: Enum.map(assigns.unmatched, &normalize_unmatched_row/1)

  defp rows_for(assigns, key) do
    case Enum.find(assigns.schemas, &(&1.key == key)) do
      nil -> []
      schema -> Enum.map(schema.matched, &normalize_matched_row/1)
    end
  end

  defp normalize_matched_row(ing) do
    %{
      id: ing.id,
      name: ing.name,
      data_type: ing.data_type,
      food_class: ing.food_class,
      reason: nil
    }
  end

  defp normalize_unmatched_row(%{ingredient: ing, reason: reason}) do
    %{
      id: ing.id,
      name: ing.name,
      data_type: ing.data_type,
      food_class: ing.food_class,
      reason: reason
    }
  end

  # Patch the in-memory lists after one ingredient is assigned — decrements its
  # schema's count, drops it from unmatched/active_rows, and reloads the (small)
  # species tables. Re-renders the 92 headers only; the streamed rows are patched
  # separately by the caller (stream_delete / restream).
  defp after_assign_data(socket, ingredient_id) do
    schemas =
      for schema <- socket.assigns.schemas do
        if Enum.any?(schema.matched, &(&1.id == ingredient_id)) do
          matched = Enum.reject(schema.matched, &(&1.id == ingredient_id))
          %{schema | matched: matched, matched_count: length(matched)}
        else
          schema
        end
      end

    unmatched = Enum.reject(socket.assigns.unmatched, &(&1.ingredient.id == ingredient_id))
    active_rows = Enum.reject(socket.assigns.active_rows, &(&1.id == ingredient_id))

    socket
    |> assign(:schemas, schemas)
    |> assign(:unmatched, unmatched)
    |> assign(:active_rows, active_rows)
    |> assign(:matched_count, schemas |> Enum.map(& &1.matched_count) |> Enum.sum())
    |> assign(:unmatched_count, length(unmatched))
    |> reload_species()
  end

  defp reload_species(socket) do
    socket
    |> assign(:species, Food.list_foundemental_species())
    |> assign(:species_with_foods, Food.list_foundemental_species_with_foods())
  end

  defp maybe_assign_pending(socket, species) do
    case socket.assigns.pending_assignment do
      %{ingredient_id: ingredient_id, usda_name: usda_name} ->
        Food.assign_foundemental_ingredient(species.id, ingredient_id, usda_name)
        socket

      nil ->
        socket
    end
  end

  defp new_species_form do
    to_form(Food.change_foundemental_species(%FoundementalFoodSpecies{}))
  end

  # ── Render helpers ──────────────────────────────────────────────────────────

  @doc """
  Searchable species picker for one curation row. Client-side (Alpine) filter
  over the small species list — no per-keystroke round-trip — pre-seeded with the
  first two letters of the row's ingredient name. Picking an option (or "+ New
  species…") pushes the shared `select_species` event via `phx-click`, so the
  create/confirm modal flow is unchanged.
  """
  def species_combobox(assigns) do
    ~H"""
    <div
      class="relative"
      x-data={"{ open: false, q: #{Jason.encode!(search_seed(@row.name))} }"}
      @click.outside="open = false"
    >
      <input
        type="text"
        x-model="q"
        value={search_seed(@row.name)}
        @focus="open = true"
        placeholder="Search species…"
        autocomplete="off"
        class="bg-ink-panel2 text-parchment border border-ink-panel2 rounded text-xs px-2 py-1 w-44 focus:outline-none"
      />
      <div
        x-show="open"
        class="absolute right-0 z-20 mt-1 w-56 max-h-56 overflow-auto rounded border border-ink-panel2 bg-ink-panel shadow-lg"
      >
        <button
          :for={s <- @species}
          type="button"
          x-show={species_match_js(s)}
          phx-click="select_species"
          phx-value-species_id={s.id}
          phx-value-ingredient_id={@row.id}
          phx-value-usda_name={@row.name}
          @click="open = false"
          class="block w-full text-left px-2 py-1 text-xs text-parchment hover:bg-ink-panel2"
        >
          {species_label(s)}
        </button>
        <p :if={@species == []} class="px-2 py-1 text-xs text-parchment-dim">No species yet.</p>
        <button
          type="button"
          phx-click="select_species"
          phx-value-species_id="__new__"
          phx-value-ingredient_id={@row.id}
          phx-value-usda_name={@row.name}
          @click="open = false"
          class="block w-full text-left px-2 py-1 text-xs text-parchment font-medium border-t border-ink-panel2 hover:bg-ink-panel2"
        >
          + New species…
        </button>
      </div>
    </div>
    """
  end

  # First two letters of the ingredient name — the search box's default query.
  defp search_seed(name), do: name |> to_string() |> String.slice(0, 2)

  # Alpine `x-show` test: the (constant) species label contains the live query.
  defp species_match_js(species) do
    "#{Jason.encode!(String.downcase(species_label(species)))}.includes(q.toLowerCase())"
  end

  def expanded?(expanded, key), do: MapSet.member?(expanded, key)

  def species_label(%{variety: v} = s) when v in [nil, ""], do: s.name
  def species_label(s), do: "#{s.name} — #{s.variety}"

  def source_label(:reference_files), do: "USDA reference datasets"
  def source_label(:ingredients), do: "ingredient corpus (no reference file)"
end
