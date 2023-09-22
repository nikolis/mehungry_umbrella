defmodule MehungryWeb.MeasurementUnitLive.FormComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Food

  @impl true
  def update(%{measurement_unit: measurement_unit} = assigns, socket) do
    changeset = Food.change_measurement_unit(measurement_unit, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"measurement_unit" => measurement_unit_params}, socket) do
    changeset =
      socket.assigns.measurement_unit
      |> Food.change_measurement_unit(measurement_unit_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"measurement_unit" => measurement_unit_params}, socket) do
    save_measurement_unit(socket, socket.assigns.action, measurement_unit_params)
  end

  defp save_measurement_unit(socket, :edit, measurement_unit_params) do
    case Food.update_measurement_unit(socket.assigns.measurement_unit, measurement_unit_params) do
      {:ok, _measurement_unit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Measurement unit updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_measurement_unit(socket, :new, measurement_unit_params) do
    case Food.create_measurement_unit(measurement_unit_params) do
      {:ok, _measurement_unit} ->
        {:noreply,
         socket
         |> put_flash(:info, "Measurement unit created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
