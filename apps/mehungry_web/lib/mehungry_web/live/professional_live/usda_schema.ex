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

  The heavy corpus parse runs on mount and explicit "Recompute" only; assigning
  an ingredient only re-queries the (small) curation tables and re-filters.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.FoundementalFoodSpecies
  alias Mehungry.FoodData.Usda.SchemaMatcher

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
      |> assign_empty_analysis()

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

  @impl true
  def handle_event("toggle", %{"key" => key}, socket) do
    expanded = socket.assigns.expanded

    expanded =
      if MapSet.member?(expanded, key),
        do: MapSet.delete(expanded, key),
        else: MapSet.put(expanded, key)

    {:noreply, assign(socket, :expanded, expanded)}
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
        {:noreply, socket |> refresh_curation() |> put_flash(:info, "Assigned to species")}

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
        socket = maybe_assign_pending(socket, species)

        {:noreply,
         socket
         |> assign(:show_species_modal, false)
         |> assign(:pending_assignment, nil)
         |> refresh_curation()
         |> put_flash(:info, "Created species \"#{species.name}\"")}

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
  # curation filter on top. Assignment events never call this; they only re-run
  # refresh_curation.
  defp load(socket) do
    analysis = SchemaMatcher.analyze()

    socket
    |> assign(:source, analysis.source)
    |> assign(:raw_schemas, analysis.schemas)
    |> assign(:raw_unmatched, analysis.unmatched)
    |> assign(:total_ingredients, analysis.total_ingredients)
    |> assign(:schema_count, analysis.schema_count)
    |> refresh_curation()
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
  # from the schema/unmatched lists, then rebuilds the species accordion.
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

  def expanded?(expanded, key), do: MapSet.member?(expanded, key)

  def species_options(species) do
    Enum.map(species, fn s ->
      label = if s.variety in [nil, ""], do: s.name, else: "#{s.name} — #{s.variety}"
      {label, s.id}
    end)
  end

  def species_label(%{variety: v} = s) when v in [nil, ""], do: s.name
  def species_label(s), do: "#{s.name} — #{s.variety}"

  def source_label(:reference_files), do: "USDA reference datasets"
  def source_label(:ingredients), do: "ingredient corpus (no reference file)"
end
