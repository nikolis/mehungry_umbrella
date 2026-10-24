defmodule MehungryWeb.ProfessionalLive.Recipes do
  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.Settings
  alias Mehungry.Food.Nutrients
  alias Mehungry.Food.NutrientRecalculationRuns
  alias Mehungry.Food.HashtagReconciliations
  alias Mehungry.ObanWorkers.HashtagReconciliationWorker
  alias Mehungry.ReconcileRecipeIngredientPortions
  alias MehungryWeb.RecipeSocialGraphicWorker

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
      |> assign(:graphic_running_id, nil)
      |> assign(:graphic_result, nil)
      |> assign(:graphic_error, nil)
      |> assign(:image_provider, Settings.image_provider())
      |> assign(:bfl_configured, Application.get_env(:mehungry, :bfl_api_key, "") != "")
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
  def handle_event("generate_graphic", %{"id" => id}, socket) do
    recipe_id = String.to_integer(id)
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, RecipeSocialGraphicWorker.topic(recipe_id))
    end

    %{recipe_id: recipe_id, user_id: user_id}
    |> RecipeSocialGraphicWorker.new()
    |> Oban.insert()

    {:noreply,
     socket
     |> assign(:graphic_running_id, recipe_id)
     |> assign(:graphic_result, nil)
     |> assign(:graphic_error, nil)}
  end

  # Flip the recipe-cover image provider (gpt-image-2 ↔ FLUX 2 pro). Persisted in
  # the shared app_settings store so it takes effect on every machine and
  # survives deploys — see Mehungry.Settings.
  @impl true
  def handle_event("set_image_provider", %{"provider" => provider}, socket) do
    Logger.info(
      "[set_image_provider] provider=#{provider} requested by user " <>
        "#{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Settings.put_image_provider(provider) do
        {:ok, _} ->
          active = Settings.image_provider()

          socket
          |> assign(:image_provider, active)
          |> put_flash(:info, "Recipe images now generated via #{provider_label(active)}.")

        {:error, reason} ->
          Logger.error("[set_image_provider] failed: #{inspect(reason)}")
          put_flash(socket, :error, "Could not change image provider.")
      end

    {:noreply, socket}
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

  # Group-manage imported recipes: delete every recipe marked `source: "myplate"`.
  @impl true
  def handle_event("delete_myplate_recipes", _params, socket) do
    Logger.info(
      "[delete_myplate_recipes] requested by user #{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Food.delete_recipes_by_source("myplate") do
        {:ok, count} ->
          socket
          |> put_flash(:info, "Deleted #{count} MyPlate-imported recipe(s).")
          |> load_stats()
          |> load_search_results(socket.assigns.search_query)

        {:error, reason} ->
          Logger.error("[delete_myplate_recipes] failed: #{inspect(reason)}")
          put_flash(socket, :error, "Deletion failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  # Group-manage imported recipes: delete every recipe marked `source: "gutenberg"`.
  @impl true
  def handle_event("delete_gutenberg_recipes", _params, socket) do
    Logger.info(
      "[delete_gutenberg_recipes] requested by user #{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Food.delete_recipes_by_source("gutenberg") do
        {:ok, count} ->
          socket
          |> put_flash(:info, "Deleted #{count} Gutenberg-imported recipe(s).")
          |> load_stats()
          |> load_search_results(socket.assigns.search_query)

        {:error, reason} ->
          Logger.error("[delete_gutenberg_recipes] failed: #{inspect(reason)}")
          put_flash(socket, :error, "Deletion failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  # Group-manage imported recipes: delete every recipe marked `source: "unitools"`.
  @impl true
  def handle_event("delete_unitools_recipes", _params, socket) do
    Logger.info(
      "[delete_unitools_recipes] requested by user #{inspect(socket.assigns[:current_user] && socket.assigns.current_user.id)}"
    )

    socket =
      case Food.delete_recipes_by_source("unitools") do
        {:ok, count} ->
          socket
          |> put_flash(:info, "Deleted #{count} UniTools-imported recipe(s).")
          |> load_stats()
          |> load_search_results(socket.assigns.search_query)

        {:error, reason} ->
          Logger.error("[delete_unitools_recipes] failed: #{inspect(reason)}")
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
  # how many were enqueued. Batched (one row upsert + one Oban.insert_all) so a
  # full-corpus resweep can't back up Oban's Postgres notifier with a per-recipe
  # NOTIFY storm — see oban_production_diagnostics.md §12.
  defp enqueue_all_reconciliations do
    HashtagReconciliations.all_recipe_ids()
    |> HashtagReconciliations.pending_or_failed()
    |> HashtagReconciliationWorker.enqueue_all()
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

  # Insight social-graphic generation result (async worker).
  @impl true
  def handle_info({:recipe_social_graphic, _recipe_id, {:ok, graphic}}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running_id, nil)
     |> assign(:graphic_result, graphic)
     |> assign(:graphic_error, nil)}
  end

  @impl true
  def handle_info({:recipe_social_graphic, _recipe_id, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:graphic_running_id, nil)
     |> assign(:graphic_error, inspect(reason))}
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

  def provider_label(:flux), do: "FLUX 2 pro"
  def provider_label(_), do: "gpt-image-2 (OpenAI)"

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

  # Progress helpers over the hashtag-reconciliation `status => count` map.
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
    |> assign(:myplate_count, Food.count_recipes_by_source("myplate"))
    |> assign(:gutenberg_count, Food.count_recipes_by_source("gutenberg"))
    |> assign(:unitools_count, Food.count_recipes_by_source("unitools"))
    |> stream(:empty_recipes, empty_recipes, reset: true)
  end

  defp load_search_results(socket, query) do
    stream(socket, :search_results, Food.search_recipes_for_admin(query), reset: true)
  end
end
