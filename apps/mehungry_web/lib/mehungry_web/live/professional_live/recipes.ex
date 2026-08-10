defmodule MehungryWeb.ProfessionalLive.Recipes do
  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.Nutrients
  alias Mehungry.Food.NutrientRecalculationRuns

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, NutrientRecalculationRuns.topic())
    end

    socket =
      socket
      |> assign(:recalc_run, NutrientRecalculationRuns.latest_run())
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

  defp load_stats(socket) do
    empty_recipes = Food.list_recipes_without_ingredients()

    socket
    |> assign(:total_count, Food.count_recipes())
    |> assign(:empty_count, length(empty_recipes))
    |> stream(:empty_recipes, empty_recipes, reset: true)
  end
end
