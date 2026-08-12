defmodule MehungryWeb.ProfessionalLive.MeasurementUnits do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.MeasurementUnit
  alias Mehungry.Food.MeasurementUnitReconciliationRuns

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, MeasurementUnitReconciliationRuns.topic())
    end

    socket =
      socket
      |> assign(:numeric_count, Food.count_numeric_named_measurement_units())
      |> assign(:junk_count, Food.count_junk_measurement_units())
      |> assign(:reconcile_run, MeasurementUnitReconciliationRuns.latest_run())
      |> stream(:measurement_units, Food.list_measurement_units())

    {:ok, socket}
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
  def handle_event("purge_junk_units", _params, socket) do
    tally = Food.purge_all_junk_measurement_units()

    {:noreply,
     socket
     |> assign(:numeric_count, Food.count_numeric_named_measurement_units())
     |> assign(:junk_count, Food.count_junk_measurement_units())
     |> stream(:measurement_units, Food.list_measurement_units(), reset: true)
     |> put_flash(
       :info,
       "Purged #{tally.units} junk unit(s): deleted #{tally.recipes} dependent recipe(s), reconciled #{tally.portions} portion(s)."
     )}
  end

  @impl true
  def handle_event("reconcile_numeric_units", _params, socket) do
    run = Food.start_measurement_unit_reconciliation_run()

    {:noreply,
     socket
     |> assign(:reconcile_run, run)
     |> put_flash(:info, "Queued #{run.total} numeric-named unit(s) for USDA reconciliation.")}
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

  # Live progress broadcast by MeasurementUnitReconciliationRuns as jobs finish.
  # Refresh the numeric-name count when the run completes so the badge settles.
  @impl true
  def handle_info({:measurement_unit_reconciliation_run, run}, socket) do
    socket = assign(socket, :reconcile_run, run)

    socket =
      if run.status == "completed" do
        assign(socket, :numeric_count, Food.count_numeric_named_measurement_units())
      else
        socket
      end

    {:noreply, socket}
  end

  def reconcile_running?(%{status: "processing"}), do: true
  def reconcile_running?(_), do: false

  def reconcile_percent(%{total: total} = run) when is_integer(total) and total > 0 do
    round((run.completed + run.failed) / total * 100)
  end

  def reconcile_percent(_), do: 0

  def reconcile_remaining(%{total: total, completed: completed, failed: failed})
      when is_integer(total) do
    max(total - completed - failed, 0)
  end

  def reconcile_remaining(_), do: 0
end
