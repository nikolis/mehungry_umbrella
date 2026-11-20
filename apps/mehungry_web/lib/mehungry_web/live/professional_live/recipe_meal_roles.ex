defmodule MehungryWeb.ProfessionalLive.RecipeMealRoles do
  @moduledoc """
  Admin review of recipe **meal roles** (`Mehungry.Food.MealRoles`) at
  `/professional/recipe-meal-roles`.

  Shows coverage + per-role counts, starts AI classification runs with live
  progress, and lists recipes (Needs review / Unclassified / Reviewed / All)
  where an admin toggles role chips — a recipe may hold several roles — then
  **Save** (explicit set) or **Confirm** (accept the AI's set). Saved and
  confirmed roles are never overwritten by the classifier.

  The list is a plain paginated assign (not a stream) because each row carries
  editable chip state that re-renders on every toggle.
  See `docs/implementation/food/meal_roles.md`.
  """

  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.{MealRoleAssignments, MealRoles, RecipeMealRoleRuns}

  @per_page 25
  @statuses [
    {"needs_review", "Needs review"},
    {"unclassified", "Unclassified"},
    {"reviewed", "Reviewed"},
    {"all", "All"}
  ]
  @sources [
    {"", "Any source"},
    {"in_app", "In-app"},
    {"myplate", "MyPlate"},
    {"gutenberg", "Gutenberg"},
    {"unitools", "UniTools"}
  ]

  # ── mount ────────────────────────────────────────────────────────────────────

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, RecipeMealRoleRuns.topic())
    end

    socket =
      socket
      |> assign(:page_title, "Meal roles")
      |> assign(:roles, MealRoles.all())
      |> assign(:statuses, @statuses)
      |> assign(:sources, @sources)
      |> assign(:filters, default_filters())
      |> assign(:drafts, %{})
      |> assign(:selected, MapSet.new())
      |> assign(:reclassifying, MapSet.new())
      |> assign(:run, RecipeMealRoleRuns.latest_run())
      |> load_coverage()
      |> load_page(reset: true)

    {:ok, socket}
  end

  defp default_filters do
    %{status: "needs_review", role: "", search: "", source: "", include_private: false}
  end

  # ── events: filters + paging ─────────────────────────────────────────────────

  @impl true
  def handle_event("set_status", %{"status" => status}, socket) do
    {:noreply, socket |> update_filters(%{status: status}) |> load_page(reset: true)}
  end

  def handle_event("filter_role", %{"role" => role}, socket) do
    role = if socket.assigns.filters.role == role, do: "", else: role
    {:noreply, socket |> update_filters(%{role: role}) |> load_page(reset: true)}
  end

  def handle_event("filter", params, socket) do
    changes = %{
      search: Map.get(params, "search", ""),
      role: Map.get(params, "role", ""),
      source: Map.get(params, "source", ""),
      include_private: Map.get(params, "include_private") == "true"
    }

    {:noreply, socket |> update_filters(changes) |> load_page(reset: true)}
  end

  def handle_event("load_more", _params, socket) do
    {:noreply, load_page(socket, reset: false)}
  end

  # ── events: per-row editing ──────────────────────────────────────────────────

  def handle_event("toggle_role", %{"id" => id, "role" => role}, socket) do
    id = String.to_integer(id)

    if MealRoles.valid?(role) do
      recipe = find_recipe(socket, id)
      current = draft_or_stored(socket.assigns.drafts, recipe)

      next =
        if role in current,
          do: List.delete(current, role),
          else: sort_roles([role | current])

      drafts =
        if next == stored_roles(recipe),
          do: Map.delete(socket.assigns.drafts, id),
          else: Map.put(socket.assigns.drafts, id, next)

      {:noreply, assign(socket, :drafts, drafts)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("discard", %{"id" => id}, socket) do
    {:noreply, update(socket, :drafts, &Map.delete(&1, String.to_integer(id)))}
  end

  def handle_event("save", %{"id" => id}, socket) do
    id = String.to_integer(id)
    roles = Map.get(socket.assigns.drafts, id) || stored_roles(find_recipe(socket, id))

    if roles == [] do
      {:noreply, put_flash(socket, :error, "Pick at least one role before saving.")}
    else
      case Food.set_recipe_meal_roles(id, roles, reviewer_id(socket)) do
        {:ok, _} ->
          {:noreply,
           socket
           |> update(:drafts, &Map.delete(&1, id))
           |> after_review([id])}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not save roles: #{inspect(reason)}")}
      end
    end
  end

  def handle_event("confirm", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:ok, _} = Food.confirm_recipe_meal_roles(id, reviewer_id(socket))
    {:noreply, after_review(socket, [id])}
  end

  def handle_event("reclassify", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Food.reclassify_recipe_meal_roles(id) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> update(:drafts, &Map.delete(&1, id))
         |> update(:reclassifying, &MapSet.put(&1, id))
         |> refresh_rows([id])}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not enqueue: #{inspect(reason)}")}
    end
  end

  # ── events: bulk ─────────────────────────────────────────────────────────────

  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)

    selected =
      if MapSet.member?(socket.assigns.selected, id),
        do: MapSet.delete(socket.assigns.selected, id),
        else: MapSet.put(socket.assigns.selected, id)

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("select_all", _params, socket) do
    ids = socket.assigns.recipes |> Enum.filter(&(&1.meal_roles != [])) |> MapSet.new(& &1.id)
    {:noreply, assign(socket, :selected, ids)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("confirm_selected", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected)
    {:ok, count} = Food.confirm_many_recipe_meal_roles(ids, reviewer_id(socket))

    {:noreply,
     socket
     |> assign(:selected, MapSet.new())
     |> after_review(ids)
     |> put_flash(:info, "Confirmed #{count} role(s) on #{length(ids)} recipe(s).")}
  end

  # ── events: classification runs ──────────────────────────────────────────────

  def handle_event("classify", %{"mode" => mode}, socket) do
    case Food.enqueue_meal_role_classification(mode) do
      {:ok, run} ->
        {:noreply,
         socket
         |> assign(:run, run)
         |> put_flash(:info, "Classification started — progress updates live.")}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A classification run is already in progress.")}
    end
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> load_coverage() |> load_page(reset: true)}
  end

  # ── PubSub ───────────────────────────────────────────────────────────────────

  @impl true
  def handle_info({:meal_role_run, run}, socket) do
    socket = assign(socket, :run, run)

    # Refresh the counts as batches land; reload the list only once the run
    # ends, so rows don't shift under a reviewer mid-run.
    socket =
      case run.status do
        "completed" -> socket |> load_coverage() |> load_page(reset: true)
        "failed" -> load_coverage(socket)
        _ -> load_coverage(socket)
      end

    {:noreply, socket}
  end

  def handle_info({:recipe_meal_roles_updated, recipe_id}, socket) do
    if MapSet.member?(socket.assigns.reclassifying, recipe_id) do
      {:noreply,
       socket
       |> update(:reclassifying, &MapSet.delete(&1, recipe_id))
       |> refresh_rows([recipe_id])
       |> load_coverage()}
    else
      {:noreply, socket}
    end
  end

  # ── data loading ─────────────────────────────────────────────────────────────

  defp update_filters(socket, changes) do
    socket
    |> assign(:filters, Map.merge(socket.assigns.filters, changes))
    |> assign(:selected, MapSet.new())
  end

  defp load_coverage(socket), do: assign(socket, :coverage, Food.meal_role_coverage())

  defp load_page(socket, reset: true) do
    recipes = fetch_page(socket.assigns.filters, 0)

    socket
    |> assign(:recipes, recipes)
    |> assign(:has_more, length(recipes) == @per_page)
  end

  defp load_page(socket, reset: false) do
    existing = socket.assigns.recipes
    more = fetch_page(socket.assigns.filters, length(existing))
    seen = MapSet.new(existing, & &1.id)

    socket
    |> assign(:recipes, existing ++ Enum.reject(more, &MapSet.member?(seen, &1.id)))
    |> assign(:has_more, length(more) == @per_page)
  end

  defp fetch_page(filters, offset) do
    Food.list_recipes_for_meal_role_review(filters, limit: @per_page, offset: offset)
  end

  # After Save / Confirm: rows leave the "Needs review" / "Unclassified" tabs
  # (they no longer match), and refresh in place elsewhere.
  defp after_review(socket, ids) do
    socket =
      if socket.assigns.filters.status in ["needs_review", "unclassified"] do
        id_set = MapSet.new(ids)
        update(socket, :recipes, fn rs -> Enum.reject(rs, &MapSet.member?(id_set, &1.id)) end)
      else
        refresh_rows(socket, ids)
      end

    load_coverage(socket)
  end

  defp refresh_rows(socket, ids) do
    fresh = Map.new(ids, &{&1, MealRoleAssignments.get_for_review(&1)})

    update(socket, :recipes, fn recipes ->
      recipes
      |> Enum.map(fn r -> Map.get(fresh, r.id, r) end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp find_recipe(socket, id), do: Enum.find(socket.assigns.recipes, &(&1.id == id))

  defp reviewer_id(socket), do: socket.assigns.current_user && socket.assigns.current_user.id

  # ── view helpers ─────────────────────────────────────────────────────────────

  defp stored_roles(nil), do: []
  defp stored_roles(recipe), do: recipe.meal_roles |> Enum.map(& &1.role) |> sort_roles()

  defp draft_or_stored(drafts, recipe) do
    Map.get(drafts, recipe && recipe.id) || stored_roles(recipe)
  end

  defp sort_roles(roles) do
    order = MealRoles.all()
    Enum.sort_by(roles, fn r -> Enum.find_index(order, &(&1 == r)) || 99 end)
  end

  defp dirty?(drafts, recipe), do: Map.has_key?(drafts, recipe.id)

  defp needs_review?(recipe), do: Enum.any?(recipe.meal_roles, &(not &1.reviewed))

  defp stored_row(recipe, role), do: Enum.find(recipe.meal_roles, &(&1.role == role))

  # Chip classes: selected/unselected × stored/added/removed × confidence.
  defp chip_class(recipe, role, drafts) do
    selected = role in draft_or_stored(drafts, recipe)
    state = chip_state(selected, stored_row(recipe, role))

    "px-2 py-0.5 rounded-full text-xs font-medium border transition-colors #{state}"
  end

  # Selected but not stored → an unsaved addition.
  defp chip_state(true, nil), do: "border-dashed border-basil text-basil bg-basil/10"
  defp chip_state(true, %{reviewed: true}), do: "border-basil bg-basil text-ink"

  defp chip_state(true, row) do
    if low_confidence?(row),
      do: "border-amber-400 text-amber-300 bg-amber-400/10",
      else: "border-basil/70 text-parchment bg-basil/20"
  end

  # Stored but deselected → an unsaved removal.
  defp chip_state(false, %{}), do: "border-red-400/60 text-red-300 line-through"
  defp chip_state(false, nil), do: "border-ink-panel2 text-parchment-dim hover:text-parchment"

  defp chip_suffix(recipe, role, drafts) do
    selected = role in draft_or_stored(drafts, recipe)

    case stored_row(recipe, role) do
      %{reviewed: true} when selected -> " ✓"
      %{confidence: c} when selected and is_number(c) -> " " <> format_confidence(c)
      _ -> ""
    end
  end

  defp low_confidence?(%{confidence: c}) when is_number(c), do: c < 0.6
  defp low_confidence?(_), do: false

  defp format_confidence(c), do: :erlang.float_to_binary(c * 1.0, decimals: 2)

  defp macros_label(recipe) do
    case MealRoleAssignments.per_serving_macros(recipe) do
      {nil, nil} -> "no nutrition"
      {kcal, nil} -> "#{kcal} kcal"
      {nil, protein} -> "#{protein} g protein"
      {kcal, protein} -> "#{kcal} kcal · #{protein} g protein"
    end
  end

  defp thumb(recipe), do: recipe.list_image_url || recipe.image_url

  defp owner_label(%{user: %{email: email}}) when is_binary(email),
    do: email |> String.split("@") |> hd()

  defp owner_label(_), do: "—"

  defp percent(_part, 0), do: 0
  defp percent(part, total), do: round(part / total * 100)

  defp running?(run), do: RecipeMealRoleRuns.running?(run)

  defp run_label(nil), do: "Idle"
  defp run_label(%{status: "pending"}), do: "Queued…"

  defp run_label(%{status: "processing"} = run),
    do: "Classifying… #{run.processed}/#{run.total}"

  defp run_label(%{status: "completed"} = run), do: "Last run: #{run.processed} recipes"
  defp run_label(%{status: "failed", error: error}), do: "Failed: #{error}"
  defp run_label(_), do: "Idle"

  defp run_class(%{status: "failed"}), do: "text-red-400"
  defp run_class(%{status: s}) when s in ["pending", "processing"], do: "text-basil"
  defp run_class(_), do: "text-parchment-dim"
end
