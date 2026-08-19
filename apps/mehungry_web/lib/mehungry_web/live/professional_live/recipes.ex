defmodule MehungryWeb.ProfessionalLive.Recipes do
  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.Nutrients
  alias Mehungry.Food.NutrientRecalculationRuns
  alias Mehungry.Food.HashtagReconciliations
  alias Mehungry.ObanWorkers.HashtagReconciliationWorker
  alias Mehungry.ReconcileRecipeIngredientPortions

  # Coalesce window for the high-frequency hashtag-reconciliation broadcasts: we
  # re-query the aggregate counts at most once per window rather than per job.
  @hashtag_flush_ms 400

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, NutrientRecalculationRuns.topic())
      Phoenix.PubSub.subscribe(Mehungry.PubSub, HashtagReconciliations.topic())
    end

    socket =
      socket
      |> assign(:recalc_run, NutrientRecalculationRuns.latest_run())
      |> assign(:portion_report, nil)
      |> assign(:portion_running, false)
      |> assign(:search_query, "")
      |> assign(:hashtag_running, false)
      |> assign(:hashtag_counts, HashtagReconciliations.counts())
      |> assign(:hashtag_flush_scheduled, false)
      |> load_stats()
      |> load_search_results("")

    {:ok, socket}
  end

  @impl true
  def handle_event("search_recipes", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:search_query, query)
     |> load_search_results(query)}
  end

  @impl true
  def handle_event("delete_recipe", %{"id" => id}, socket) do
    id = String.to_integer(id)

    Logger.info(
      "[delete_recipe] recipe=#{id} requested by user " <>
        "#{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Food.delete_recipes_by_ids([id]) do
        {:ok, count} when count > 0 ->
          socket
          |> put_flash(:info, "Deleted recipe ##{id} and all its references.")
          |> load_stats()
          |> load_search_results(socket.assigns.search_query)

        {:ok, _} ->
          put_flash(socket, :error, "Recipe ##{id} not found.")

        {:error, reason} ->
          Logger.error("[delete_recipe] recipe=#{id} failed: #{inspect(reason)}")
          put_flash(socket, :error, "Deletion failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete_without_ingredients", _params, socket) do
    Logger.info(
      "[delete_recipes_without_ingredients] requested by user #{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Food.delete_recipes_without_ingredients() do
        {:ok, count} ->
          socket
          |> put_flash(:info, "Deleted #{count} recipe(s) with no ingredients.")
          |> load_stats()

        {:error, reason} ->
          Logger.error("[delete_recipes_without_ingredients] failed: #{inspect(reason)}")
          put_flash(socket, :error, "Deletion failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("recompute_nutrients", _params, socket) do
    Logger.info(
      "[recompute_all_recipe_nutrients] requested by user #{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    run = Nutrients.start_full_recalculation_run()

    socket =
      socket
      |> assign(:recalc_run, run)
      |> put_flash(:info, "Queued #{run.total} recipe(s) for nutrient recomputation.")

    {:noreply, socket}
  end

  # Reconcile legacy RecipeIngredient rows onto the IngredientPortion model.
  # `dry_run` only assesses (no writes); otherwise it backfills, synthesizes
  # missing mass/volume portions, and reports the unresolvable pairs for review.
  # See Mehungry.ReconcileRecipeIngredientPortions.
  @impl true
  def handle_event("reconcile_portions", params, socket) do
    if socket.assigns.portion_running do
      {:noreply, socket}
    else
      dry_run? = params["dry_run"] == "true"

      Logger.info(
        "[reconcile_recipe_ingredient_portions] dry_run=#{dry_run?} requested by user " <>
          "#{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
      )

      socket =
        socket
        |> assign(:portion_running, true)
        |> start_async(:reconcile_portions, fn ->
          ReconcileRecipeIngredientPortions.run(dry_run: dry_run?)
        end)

      {:noreply, socket}
    end
  end

  @impl true
  def handle_async(:reconcile_portions, {:ok, report}, socket) do
    verb = if report.dry_run, do: "Assessed", else: "Reconciled"

    socket =
      socket
      |> assign(:portion_running, false)
      |> assign(:portion_report, report)
      |> put_flash(
        :info,
        "#{verb} recipe ingredients: #{report.backfilled} linked, " <>
          "#{report.description_linked} named-linked, " <>
          "#{report.synthesized_portions} portion(s) created, " <>
          "#{length(report.unresolved)} pair(s) need review."
      )

    {:noreply, socket}
  end

  @impl true
  def handle_async(:reconcile_portions, {:exit, reason}, socket) do
    Logger.error("[reconcile_recipe_ingredient_portions] crashed: #{inspect(reason)}")

    socket =
      socket
      |> assign(:portion_running, false)
      |> put_flash(:error, "Reconciliation failed: #{inspect(reason)}")

    {:noreply, socket}
  end

  # Fan out one HashtagReconciliationWorker job per not-yet-completed recipe. Each
  # job runs the shared Food.ensure_recipe_hashtags/1 — reconnecting description
  # #tags and (re)attaching #vegan/#vegetarian. Durable per-recipe tracking rows
  # drive the live progress counts below (Oban-UI-connected pattern).
  @impl true
  def handle_event("reconcile_hashtags", _params, socket) do
    if socket.assigns.hashtag_running do
      {:noreply, socket}
    else
      Logger.info(
        "[reconcile_hashtags] requested by user " <>
          "#{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
      )

      socket =
        socket
        |> assign(:hashtag_running, true)
        |> start_async(:reconcile_hashtags, &enqueue_all_reconciliations/0)

      {:noreply, socket}
    end
  end

  # Enqueues a reconciliation job for every recipe not already completed, returning
  # how many were enqueued.
  defp enqueue_all_reconciliations do
    HashtagReconciliations.all_recipe_ids()
    |> HashtagReconciliations.pending_or_failed()
    |> Enum.count(fn recipe_id ->
      match?({:ok, _job}, HashtagReconciliationWorker.enqueue(recipe_id))
    end)
  end

  @impl true
  def handle_event("reset_hashtag_reconciliation", _params, socket) do
    HashtagReconciliations.reset()

    {:noreply,
     socket
     |> assign(:hashtag_running, false)
     |> assign(:hashtag_counts, HashtagReconciliations.counts())
     |> put_flash(:info, "Hashtag reconciliation status cleared.")}
  end

  @impl true
  def handle_async(:reconcile_hashtags, {:ok, enqueued}, socket) do
    socket =
      socket
      |> assign(:hashtag_counts, HashtagReconciliations.counts())
      |> put_flash(
        :info,
        "Queued #{enqueued} recipe(s) for hashtag reconciliation."
      )

    {:noreply, socket}
  end

  @impl true
  def handle_async(:reconcile_hashtags, {:exit, reason}, socket) do
    Logger.error("[reconcile_hashtags] enqueue crashed: #{inspect(reason)}")

    socket =
      socket
      |> assign(:hashtag_running, false)
      |> put_flash(:error, "Failed to enqueue hashtag reconciliation.")

    {:noreply, socket}
  end

  # Live progress broadcast by NutrientRecalculationRuns as worker jobs finish.
  @impl true
  def handle_info({:nutrient_recalculation_run, run}, socket) do
    {:noreply, assign(socket, :recalc_run, run)}
  end

  # High-frequency per-recipe reconciliation broadcasts (full-row terminal and
  # lightweight processing): don't re-query per message. Arm a single flush timer
  # and refresh the aggregate counts once per window.
  @impl true
  def handle_info({:hashtag_recon, _reconciliation}, socket) do
    {:noreply, arm_hashtag_flush(socket)}
  end

  @impl true
  def handle_info({:hashtag_recon_processing, _recipe_id}, socket) do
    {:noreply, arm_hashtag_flush(socket)}
  end

  @impl true
  def handle_info(:flush_hashtag_counts, socket) do
    counts = HashtagReconciliations.counts()
    in_flight = Map.get(counts, "pending", 0) + Map.get(counts, "processing", 0)

    {:noreply,
     socket
     |> assign(:hashtag_counts, counts)
     |> assign(:hashtag_flush_scheduled, false)
     |> assign(:hashtag_running, in_flight > 0)}
  end

  def recalc_running?(%{status: "processing"}), do: true
  def recalc_running?(_), do: false

  def recalc_percent(%{total: total} = run) when is_integer(total) and total > 0 do
    round((run.completed + run.failed) / total * 100)
  end

  def recalc_percent(_), do: 0

  def recalc_remaining(%{total: total, completed: completed, failed: failed})
      when is_integer(total) do
    max(total - completed - failed, 0)
  end

  def recalc_remaining(_), do: 0

  def portion_reason_label(:no_conversion),
    do: "unit has no mass/volume conversion — remap the unit or add a portion by hand"

  def portion_reason_label(:no_anchor_portion),
    do: "no existing portion to derive density from — add one portion for this ingredient"

  def portion_reason_label(_), do: "needs review"

  # Schedules the coalesced counts refresh at most once per window.
  defp arm_hashtag_flush(socket) do
    if socket.assigns.hashtag_flush_scheduled do
      socket
    else
      Process.send_after(self(), :flush_hashtag_counts, @hashtag_flush_ms)
      assign(socket, :hashtag_flush_scheduled, true)
    end
  end

  def hashtag_total(counts), do: counts |> Map.values() |> Enum.sum()

  def hashtag_done(counts),
    do: Map.get(counts, "completed", 0) + Map.get(counts, "failed", 0)

  def hashtag_percent(counts) do
    total = hashtag_total(counts)
    if total > 0, do: round(hashtag_done(counts) / total * 100), else: 0
  end

  defp load_stats(socket) do
    empty_recipes = Food.list_recipes_without_ingredients()

    socket
    |> assign(:total_count, Food.count_recipes())
    |> assign(:empty_count, length(empty_recipes))
    |> stream(:empty_recipes, empty_recipes, reset: true)
  end

  defp load_search_results(socket, query) do
    stream(socket, :search_results, Food.search_recipes_for_admin(query), reset: true)
  end
end
