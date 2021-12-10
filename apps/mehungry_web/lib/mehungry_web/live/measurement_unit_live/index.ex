defmodule MehungryWeb.MeasurementUnitLive.Index do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.MeasurementUnit

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :measurement_units, list_measurement_units())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Measurement unit")
    |> assign(:measurement_unit, Food.get_measurement_unit!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Measurement unit")
    |> assign(:measurement_unit, %MeasurementUnit{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Measurement units")
    |> assign(:measurement_unit, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    measurement_unit = Food.get_measurement_unit!(id)
    {:ok, _} = Food.delete_measurement_unit(measurement_unit)

    {:noreply, assign(socket, :measurement_units, list_measurement_units())}
  end

  defp list_measurement_units do
    Food.list_measurement_units()
  end
end
