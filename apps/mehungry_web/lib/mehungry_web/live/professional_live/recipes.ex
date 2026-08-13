defmodule MehungryWeb.ProfessionalLive.Recipes do
  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.Nutrients
  alias Mehungry.Food.NutrientRecalculationRuns
  alias Mehungry.ReconcileRecipeIngredientPortions

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, NutrientRecalculationRuns.topic())
    end

    socket =
      socket
      |> assign(:recalc_run, NutrientRecalculationRuns.latest_run())
      |> assign(:portion_report, nil)
      |> assign(:portion_running, false)
      |> load_stats()

    {:ok, socket}
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

  # Live progress broadcast by NutrientRecalculationRuns as worker jobs finish.
  @impl true
  def handle_info({:nutrient_recalculation_run, run}, socket) do
    {:noreply, assign(socket, :recalc_run, run)}
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

  defp load_stats(socket) do
    empty_recipes = Food.list_recipes_without_ingredients()

    socket
    |> assign(:total_count, Food.count_recipes())
    |> assign(:empty_count, length(empty_recipes))
    |> stream(:empty_recipes, empty_recipes, reset: true)
  end
end
