defmodule MehungryWeb.ProfessionalLive.MeasurementUnitLive.FormComponent do
  use MehungryWeb, :live_component

  alias Mehungry.Food

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.header>
        {@title}
      </.header>

      <.simple_form
        for={@form}
        id="measurement-unit-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <.input field={@form[:name]} label="Name" />
        <.input field={@form[:alternate_name]} label="Alternate name" />
        <.input field={@form[:url]} label="URL" />

        <:actions>
          <.button phx-disable-with="Saving...">
            Save Measurement Unit
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  @impl true
  def update(%{measurement_unit: measurement_unit} = assigns, socket) do
    changeset = Food.change_measurement_unit(measurement_unit, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"measurement_unit" => params}, socket) do
    changeset =
      socket.assigns.measurement_unit
      |> Food.change_measurement_unit(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"measurement_unit" => params}, socket) do
    save_measurement_unit(socket, socket.assigns.action, params)
  end

  defp save_measurement_unit(socket, :edit, params) do
    case Food.update_measurement_unit(socket.assigns.measurement_unit, params) do
      {:ok, unit} ->
        notify_parent({:saved, unit})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_measurement_unit(socket, :new, params) do
    case Food.create_measurement_unit(params) do
      {:ok, unit} ->
        notify_parent({:saved, unit})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
