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
  alias MehungryWeb.ProfessionalLive.ImportReviewSearch

  # Rows rendered per schema panel before "Show more".
  @page 100

  # Max search results shown in the Find & assign console (a name search rarely
  # needs more; keeps the streamed list cheap).
  @results_page 300

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
      |> assign(:query, "")
      |> assign(:selected, MapSet.new())
      |> assign(:result_ids, [])
      |> assign(:results_capped, false)
      |> assign(:move_selected, MapSet.new())
      |> assign_empty_analysis()
      |> stream(:rows, [])
      |> stream(:results, [])

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

  # Recompute reruns the full-corpus parse, which is as heavy as the initial
  # load. Defer it off the event handler (same async hop as mount) so the socket
  # paints the "Computing…" state first instead of freezing, and so the
  # @loading-gated button can't queue a second parse mid-run.
  def handle_info(:recompute, socket) do
    {:noreply,
     socket
     |> load()
     |> assign(:loading, false)
     |> put_flash(:info, "Recomputed from current ingredients")}
  end

  @impl true
  def handle_event("recompute", _params, socket) do
    send(self(), :recompute)
    {:noreply, assign(socket, :loading, true)}
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

  # ── Find & assign console (search → multi-select → batch assign) ──────────────

  # Name search across the whole un-curated universe. A single term or several
  # (AND-matched) rank via the shared ImportReviewSearch ranker; a blank query
  # shows nothing (never dumps all ~5k rows). Selection persists across queries.
  def handle_event("search", %{"q" => q}, socket) do
    results = search_results(socket.assigns.universe, q)

    {:noreply,
     socket
     |> assign(:query, q)
     |> assign(:result_ids, Enum.map(results, & &1.id))
     |> assign(:results_capped, length(results) == @results_page)
     |> stream(:results, results, reset: true)}
  end

  # Toggle one row's membership in the selection; re-insert that single row so its
  # checkbox re-renders (one-row diff, not a re-stream).
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    selected = toggle_member(socket.assigns.selected, id)
    socket = assign(socket, :selected, selected)

    socket =
      case Map.get(socket.assigns.universe, id) do
        nil -> socket
        row -> stream_insert(socket, :results, row)
      end

    {:noreply, socket}
  end

  def handle_event("select_all", _params, socket) do
    selected = MapSet.union(socket.assigns.selected, MapSet.new(socket.assigns.result_ids))
    {:noreply, socket |> assign(:selected, selected) |> restream_results()}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, socket |> assign(:selected, MapSet.new()) |> restream_results()}
  end

  # Tray species picker — assign the whole current selection. Mirrors the per-row
  # `select_species` flow but reads the batch from `@selected`.
  def handle_event("choose_species", %{"species_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("choose_species", %{"species_id" => "__new__"}, socket) do
    case selected_ingredients(socket) do
      [] -> {:noreply, socket}
      ingredients -> {:noreply, open_new_species_modal(socket, ingredients)}
    end
  end

  def handle_event("choose_species", %{"species_id" => species_id}, socket) do
    case selected_ingredients(socket) do
      [] ->
        {:noreply, socket}

      ingredients ->
        {:noreply, open_assign_modal(socket, ingredients, String.to_integer(species_id))}
    end
  end

  # ── Move curated leaves between species (fix a mis-assignment) ─────────────────

  def handle_event("toggle_move_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, :move_selected, toggle_member(socket.assigns.move_selected, id))}
  end

  def handle_event("clear_move_selection", _params, socket) do
    {:noreply, assign(socket, :move_selected, MapSet.new())}
  end

  # Tray destination picker for the move selection. "__new__" creates the species
  # then moves the leaves onto it; an existing id opens the confirm modal.
  def handle_event("move_choose_species", %{"species_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("move_choose_species", %{"species_id" => "__new__"}, socket) do
    case selected_move_ingredients(socket) do
      [] -> {:noreply, socket}
      ingredients -> {:noreply, open_new_species_modal(socket, ingredients, :move)}
    end
  end

  def handle_event("move_choose_species", %{"species_id" => species_id}, socket) do
    case selected_move_ingredients(socket) do
      [] ->
        {:noreply, socket}

      ingredients ->
        {:noreply, open_move_modal(socket, ingredients, String.to_integer(species_id))}
    end
  end

  # ── Per-row combobox (demoted Structural view) — a batch of one ───────────────

  # Blank selection ("— assign species —") is a no-op.
  def handle_event("select_species", %{"species_id" => ""}, socket), do: {:noreply, socket}

  def handle_event(
        "select_species",
        %{"species_id" => "__new__", "ingredient_id" => ingredient_id, "usda_name" => usda_name},
        socket
      ) do
    ingredients = [%{id: String.to_integer(ingredient_id), name: usda_name}]
    {:noreply, open_new_species_modal(socket, ingredients)}
  end

  def handle_event(
        "select_species",
        %{"species_id" => species_id, "ingredient_id" => ingredient_id, "usda_name" => usda_name},
        socket
      ) do
    ingredients = [%{id: String.to_integer(ingredient_id), name: usda_name}]
    {:noreply, open_assign_modal(socket, ingredients, String.to_integer(species_id))}
  end

  # Submit of the confirmation modal for an existing species — assigns the batch
  # (fresh curation) or moves it (re-curation), per the pending `:mode`.
  def handle_event("confirm_assignment", _params, socket) do
    %{ingredients: ingredients, species_id: species_id} =
      pending = socket.assigns.pending_assignment

    socket =
      socket
      |> assign(:show_assign_modal, false)
      |> assign(:pending_assignment, nil)

    case Map.get(pending, :mode, :assign) do
      :assign ->
        {:ok, %{assigned: assigned, skipped: skipped}} =
          Food.assign_foundemental_ingredients(species_id, pairs_for(ingredients))

        {:noreply,
         socket
         |> after_assign_data(Enum.map(ingredients, & &1.id))
         |> put_flash(:info, assign_flash(assigned, skipped))}

      :move ->
        {:ok, %{moved: moved}} =
          Food.move_foundemental_ingredients(species_id, Enum.map(ingredients, & &1.id))

        {:noreply,
         socket
         |> assign(:move_selected, MapSet.new())
         |> reload_species()
         |> put_flash(:info, "Moved #{moved} #{ngettext_ingredient(moved)}")}
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

        socket =
          socket
          |> assign(:show_species_modal, false)
          |> assign(:pending_assignment, nil)
          |> finish_create_species(species, pending)

        {:noreply, socket}

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

  # Per-species visibility toggle. A private species is hidden from every public
  # surface (/foods browse, search, filter, directory, detail page, sitemap,
  # mobile API) but stays here for curation.
  def handle_event("toggle_species_private", %{"species_id" => id}, socket) do
    species = Food.get_foundemental_species!(id)

    case Food.update_foundemental_species(species, %{"private" => !species.private}) do
      {:ok, updated} ->
        flash =
          if updated.private,
            do: "“#{updated.name}” is now private (hidden from /foods)",
            else: "“#{updated.name}” is now public"

        {:noreply, socket |> reload_species() |> put_flash(:info, flash)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update visibility")}
    end
  end

  # Per-species emoji override. A blank value clears the override, so the row
  # falls back to the name/family-derived default from `Food.species_icon/1`.
  def handle_event("update_species_icon", %{"species_id" => id, "icon" => icon}, socket) do
    icon = String.trim(icon)
    icon = if icon == "", do: nil, else: icon
    species = Food.get_foundemental_species!(id)

    case Food.update_foundemental_species(species, %{"icon" => icon}) do
      {:ok, _species} ->
        {:noreply, reload_species(socket)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update icon")}
    end
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
    |> assign(:universe, %{})
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
    |> assign(:universe, build_universe(schemas, unmatched))
    |> reload_species()
  end

  # The flat, searchable set of every *un-curated* ingredient — the union of all
  # schemas' matched rows and the unmatched entries (both already minus the
  # assigned ids). Keyed by id for O(1) lookup when resolving a selection to
  # assign. This is the corpus the Find & assign console searches.
  defp build_universe(schemas, unmatched) do
    matched = Enum.flat_map(schemas, & &1.matched)
    unmatched_ings = Enum.map(unmatched, & &1.ingredient)

    (matched ++ unmatched_ings)
    |> Map.new(fn ing -> {ing.id, %{id: ing.id, name: ing.name, data_type: ing.data_type}} end)
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

  # Re-stream the currently visible search results so their checkboxes reflect the
  # latest `@selected` (used by select-all / clear, which touch many rows at once).
  defp restream_results(socket) do
    rows =
      socket.assigns.result_ids
      |> Enum.map(&Map.get(socket.assigns.universe, &1))
      |> Enum.reject(&is_nil/1)

    stream(socket, :results, rows, reset: true)
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
    %{id: ing.id, name: ing.name, data_type: ing.data_type, reason: nil}
  end

  defp normalize_unmatched_row(%{ingredient: ing, reason: reason}) do
    %{id: ing.id, name: ing.name, data_type: ing.data_type, reason: reason}
  end

  # Patch the in-memory lists after a batch of ingredients is assigned — decrements
  # their schemas' counts, drops them from unmatched/active_rows/universe/selection,
  # stream-deletes them from both the console (:results) and the accordion (:rows),
  # and reloads the (small) species tables.
  defp after_assign_data(socket, ingredient_ids) do
    id_set = MapSet.new(ingredient_ids)

    schemas =
      for schema <- socket.assigns.schemas do
        if Enum.any?(schema.matched, &MapSet.member?(id_set, &1.id)) do
          matched = Enum.reject(schema.matched, &MapSet.member?(id_set, &1.id))
          %{schema | matched: matched, matched_count: length(matched)}
        else
          schema
        end
      end

    unmatched = Enum.reject(socket.assigns.unmatched, &MapSet.member?(id_set, &1.ingredient.id))
    active_rows = Enum.reject(socket.assigns.active_rows, &MapSet.member?(id_set, &1.id))
    result_ids = Enum.reject(socket.assigns.result_ids, &MapSet.member?(id_set, &1))

    socket =
      Enum.reduce(ingredient_ids, socket, fn id, acc ->
        acc
        |> stream_delete(:rows, %{id: id})
        |> stream_delete(:results, %{id: id})
      end)

    socket
    |> assign(:schemas, schemas)
    |> assign(:unmatched, unmatched)
    |> assign(:active_rows, active_rows)
    |> assign(:result_ids, result_ids)
    |> assign(:universe, Map.drop(socket.assigns.universe, ingredient_ids))
    |> assign(:selected, MapSet.difference(socket.assigns.selected, id_set))
    |> assign(:matched_count, schemas |> Enum.map(& &1.matched_count) |> Enum.sum())
    |> assign(:unmatched_count, length(unmatched))
    |> reload_species()
  end

  defp reload_species(socket) do
    socket
    |> assign(:species, Food.list_foundemental_species())
    |> assign(:species_with_foods, Food.list_foundemental_species_with_foods())
  end

  # Wire a freshly created species to its pending batch — either curate the batch
  # onto it (assign) or re-point already-curated leaves onto it (move), per `:mode`.
  # `restream_active/1` refreshes the accordion rows so their comboboxes include
  # the new species.
  defp finish_create_species(socket, species, %{ingredients: ingredients, mode: :move}) do
    {:ok, %{moved: moved}} =
      Food.move_foundemental_ingredients(species.id, Enum.map(ingredients, & &1.id))

    socket
    |> assign(:move_selected, MapSet.new())
    |> reload_species()
    |> put_flash(
      :info,
      "Created “#{species.name}” — moved #{moved} #{ngettext_ingredient(moved)}"
    )
  end

  defp finish_create_species(socket, species, %{ingredients: ingredients}) do
    {:ok, %{assigned: assigned, skipped: skipped}} =
      Food.assign_foundemental_ingredients(species.id, pairs_for(ingredients))

    socket
    |> after_assign_data(Enum.map(ingredients, & &1.id))
    |> restream_active()
    |> put_flash(:info, "Created “#{species.name}” — #{assign_flash(assigned, skipped)}")
  end

  defp finish_create_species(socket, species, _pending) do
    socket
    |> reload_species()
    |> put_flash(:info, "Created species “#{species.name}”")
  end

  defp new_species_form do
    to_form(Food.change_foundemental_species(%FoundementalFoodSpecies{}))
  end

  # ── Find & assign helpers ─────────────────────────────────────────────────────

  defp search_results(_universe, q) when q in [nil, ""], do: []

  defp search_results(universe, q) do
    universe
    |> Map.values()
    |> ImportReviewSearch.filter(q, & &1.name)
    |> Enum.take(@results_page)
  end

  defp toggle_member(set, id) do
    if MapSet.member?(set, id), do: MapSet.delete(set, id), else: MapSet.put(set, id)
  end

  # The current console selection resolved to `%{id, name}` from the universe (ids
  # that have since left the universe are dropped).
  defp selected_ingredients(socket) do
    socket.assigns.selected
    |> MapSet.to_list()
    |> Enum.map(&Map.get(socket.assigns.universe, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&%{id: &1.id, name: &1.name})
  end

  # The current leaf (move) selection resolved to `%{id, name}` from the curated
  # `species_with_foods`, so a move knows each ingredient's usda_name label.
  defp selected_move_ingredients(socket) do
    lookup = leaf_lookup(socket.assigns.species_with_foods)

    socket.assigns.move_selected
    |> MapSet.to_list()
    |> Enum.filter(&Map.has_key?(lookup, &1))
    |> Enum.map(&%{id: &1, name: Map.fetch!(lookup, &1)})
  end

  defp leaf_lookup(species_with_foods) do
    for s <- species_with_foods, f <- s.foundemental_foods, into: %{} do
      {f.ingredient_id, f.usda_name}
    end
  end

  defp pairs_for(ingredients) do
    Enum.map(ingredients, fn %{id: id, name: name} -> %{ingredient_id: id, usda_name: name} end)
  end

  defp open_new_species_modal(socket, ingredients, mode \\ :assign) do
    socket
    |> assign(:pending_assignment, %{ingredients: ingredients, mode: mode})
    |> assign(:species_form, new_species_form())
    |> assign(:show_species_modal, true)
  end

  defp open_assign_modal(socket, ingredients, species_id) do
    socket
    |> assign(:pending_assignment, pending_for(socket, ingredients, species_id, :assign))
    |> assign(:show_assign_modal, true)
  end

  defp open_move_modal(socket, ingredients, species_id) do
    socket
    |> assign(:pending_assignment, pending_for(socket, ingredients, species_id, :move))
    |> assign(:show_assign_modal, true)
  end

  defp pending_for(socket, ingredients, species_id, mode) do
    species = Enum.find(socket.assigns.species, &(&1.id == species_id))

    %{
      ingredients: ingredients,
      species_id: species_id,
      species_label: species && species_label(species),
      mode: mode
    }
  end

  defp assign_flash(assigned, 0),
    do: "Assigned #{assigned} #{ngettext_ingredient(assigned)}"

  defp assign_flash(assigned, skipped),
    do: "Assigned #{assigned}; skipped #{skipped} already assigned"

  defp ngettext_ingredient(1), do: "ingredient"
  defp ngettext_ingredient(_), do: "ingredients"

  # ── Render helpers ──────────────────────────────────────────────────────────

  @doc """
  Searchable species picker for one curation row (demoted Structural view).
  Client-side (Alpine) filter over the small species list — no per-keystroke
  round-trip — starting empty. Picking an option (or "+ New species…") pushes the
  shared `select_species` event via `phx-click`, so the create/confirm modal flow
  is unchanged.
  """
  def species_combobox(assigns) do
    ~H"""
    <div class="relative" x-data="{ open: false, q: '' }" @click.outside="open = false">
      <input
        type="text"
        x-model="q"
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

  @doc """
  Destination species picker for a sticky tray — applies to the **whole** current
  selection. Same Alpine client-filter as `species_combobox/1`, but pushes `@event`
  (no per-row ingredient context; the batch is read server-side). Reused by both
  the Find & assign tray (`choose_species`) and the move tray (`move_choose_species`).
  """
  attr :species, :list, required: true
  attr :event, :string, required: true
  attr :label, :string, required: true

  def tray_species_combobox(assigns) do
    ~H"""
    <div class="relative" x-data="{ open: false, q: '' }" @click.outside="open = false">
      <button
        type="button"
        @click="open = !open"
        class="bg-paprika text-white rounded text-xs px-3 py-1.5 font-medium hover:opacity-90"
      >
        {@label} ▾
      </button>
      <div
        x-show="open"
        class="absolute right-0 bottom-full z-30 mb-1 w-64 max-h-64 overflow-auto rounded border border-ink-panel2 bg-ink-panel shadow-lg"
      >
        <div class="p-1 border-b border-ink-panel2">
          <input
            type="text"
            x-model="q"
            placeholder="Search species…"
            autocomplete="off"
            class="w-full bg-ink-panel2 text-parchment border border-ink-panel2 rounded text-xs px-2 py-1 focus:outline-none"
          />
        </div>
        <button
          :for={s <- @species}
          type="button"
          x-show={species_match_js(s)}
          phx-click={@event}
          phx-value-species_id={s.id}
          @click="open = false"
          class="block w-full text-left px-2 py-1 text-xs text-parchment hover:bg-ink-panel2"
        >
          {species_label(s)}
        </button>
        <p :if={@species == []} class="px-2 py-1 text-xs text-parchment-dim">No species yet.</p>
        <button
          type="button"
          phx-click={@event}
          phx-value-species_id="__new__"
          @click="open = false"
          class="block w-full text-left px-2 py-1 text-xs text-parchment font-medium border-t border-ink-panel2 hover:bg-ink-panel2"
        >
          + New species…
        </button>
      </div>
    </div>
    """
  end

  # Alpine `x-show` test: the (constant) species label contains the live query.
  defp species_match_js(species) do
    "#{Jason.encode!(String.downcase(species_label(species)))}.includes(q.toLowerCase())"
  end

  def expanded?(expanded, key), do: MapSet.member?(expanded, key)

  # Human summary of the pending batch for the modals ("“Apples, raw” + 6 more").
  def assignment_label([]), do: "No ingredients"
  def assignment_label([%{name: name}]), do: "“#{name}”"
  def assignment_label([%{name: name} | rest]), do: "“#{name}” + #{length(rest)} more"

  def species_label(%{variety: v} = s) when v in [nil, ""], do: s.name
  def species_label(s), do: "#{s.name} — #{s.variety}"

  def source_label(:reference_files), do: "USDA reference datasets"
  def source_label(:ingredients), do: "ingredient corpus (no reference file)"
end
