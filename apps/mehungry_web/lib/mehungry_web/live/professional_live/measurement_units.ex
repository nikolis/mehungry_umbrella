defmodule MehungryWeb.ProfessionalLive.MeasurementUnits do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.MeasurementUnit

  @impl true
  def mount(_params, _session, socket) do
    {:ok, stream(socket, :measurement_units, Food.list_measurement_units())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Measurement Unit")
    |> assign(:measurement_unit, Food.get_measurement_unit!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Measurement Unit")
    |> assign(:measurement_unit, %MeasurementUnit{})
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, :measurement_unit, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    measurement_unit = Food.get_measurement_unit!(id)

    case Food.delete_measurement_unit(measurement_unit) do
      {:ok, _} ->
        {:noreply,
         socket
         |> stream_delete(:measurement_units, measurement_unit)
         |> put_flash(:info, "Measurement unit deleted.")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot delete measurement unit — it may be used by ingredient portions."
         )}
    end
  end

  @impl true
  def handle_info(
        {MehungryWeb.ProfessionalLive.MeasurementUnitLive.FormComponent, {:saved, unit}},
        socket
      ) do
    {:noreply,
     socket
     |> stream_insert(:measurement_units, unit)
     |> push_patch(to: ~p"/professional/measurement_units")}
  end
end
