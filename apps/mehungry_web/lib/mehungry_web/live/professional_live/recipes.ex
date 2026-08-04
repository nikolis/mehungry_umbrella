defmodule MehungryWeb.ProfessionalLive.Recipes do
  use MehungryWeb, :live_view

  require Logger

  alias Mehungry.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load_stats(socket)}
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

  defp load_stats(socket) do
    empty_recipes = Food.list_recipes_without_ingredients()

    socket
    |> assign(:total_count, Food.count_recipes())
    |> assign(:empty_count, length(empty_recipes))
    |> stream(:empty_recipes, empty_recipes, reset: true)
  end
end
