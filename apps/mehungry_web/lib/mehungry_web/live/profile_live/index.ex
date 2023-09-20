defmodule MehungryWeb.ProfileLive.Index do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search

  alias Mehungry.Food
  alias MehungryWeb.CommonComponents.RecipeComponents
  alias Mehungry.Accounts

  @impl true
  def mount(_params, session, socket) do
    {recipes, _cursor_after} = list_recipes()
    user = Accounts.get_user_by_session_token(session["user_token"])

    {:ok,
     assign(socket, :content_state, :created)
     |> assign(
       :invocations,
       case Map.get(socket.assigns, :invocations) do
         nil ->
           1

         x ->
           x + 1
       end
     )
     |> assign(:recipe, nil)
     |> assign(:user, user)
     |> assign(:page, 1)
     |> assign(:counter, 1)
     |> assign(:recipes, recipes)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => _id}) do
    socket
    |> assign(:page_title, "Edit Measurement unit")
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Measurement unit")

    # |> assign(:measurement_unit, %MeasurementUnit{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Profile")
  end

  def get_active(state, param) do
    if state == param do
      "active"
    else
      ""
    end
  end

  @impl true
  def handle_event("load-more", _, socket) do
    cursor_after = Map.get(socket.assigns, :cursor_after)

    {recipes, cursor_after} = Food.list_recipes(cursor_after)

    # all_recipes  = socket.assigns.recipes ++ recipes

    {:noreply,
     socket
     |> assign(:cursor_after, cursor_after)
     |> assign(:page, socket.assigns.page + 1)
     |> assign(:recipes, recipes)}
  end

  def handle_event("delete", %{"id" => _id}, socket) do
    # measurement_unit = food.get_measurement_unit!(id)
    # {:ok, _} = food.delete_measurement_unit(measurement_unit)

    # assign(socket, :measurement_units, list_measurement_units())}
    {:noreply, socket}
  end

  @impl true
  def handle_event("content_state_change", %{"state" => state}, socket) do
    case state do
      "created" ->
        {:noreply,
         socket
         |> assign(content_state: :created)}

      "saved" ->
        {:noreply,
         socket
         |> assign(content_state: :saved)}
    end
  end

  defp list_recipes do
    {result, cursor_after} = Food.list_recipes(nil)
    {result, cursor_after}
  end
end
