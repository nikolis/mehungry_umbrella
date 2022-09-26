defmodule MehungryWeb.IngredientLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.Ingredient

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :ingredients, list_ingredients())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Ingredient")
    |> assign(:ingredient, Food.get_ingredient!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Ingredient")
    |> assign(:ingredient, %Ingredient{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Ingredients")
    |> assign(:ingredient, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    ingredient = Food.get_ingredient!(id)
    {:ok, _} = Food.delete_ingredient(ingredient)

    {:noreply, assign(socket, :ingredients, list_ingredients())}
  end

  defp list_ingredients do
    Food.list_ingredients()
  end
end
