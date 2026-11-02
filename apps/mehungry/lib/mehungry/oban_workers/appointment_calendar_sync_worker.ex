defmodule Mehungry.ObanWorkers.AppointmentCalendarSyncWorker do
  @moduledoc """
  Pushes appointment changes to a nutritionist's connected Google Calendar off
  the request cycle, so Google latency/failure never blocks accept/decline/cancel.

  Enqueued with an `"action"`:

    * `"upsert"` — create or patch the calendar event (Meet link + client
      attendee) for an accepted / rescheduled appointment;
    * `"delete"` — remove the event (on decline/cancel).

  Any Google error is a best-effort miss: the appointment keeps its manual
  `meeting_url` fallback. A missing connection or un-pushed event is a no-op.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  require Logger

  alias Mehungry.Professionals
  alias Mehungry.Professionals.GoogleCalendar

  @doc "Enqueue a calendar sync for an appointment (`:upsert` | `:delete`)."
  def enqueue(action, appointment_id) when action in [:upsert, :delete] do
    %{"action" => to_string(action), "appointment_id" => appointment_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => id, "action" => action}}) do
    case Professionals.get_appointment(id) do
      nil ->
        :ok

      appointment ->
        run(action, appointment)
    end
  end

  defp run("upsert", appointment) do
    case GoogleCalendar.sync_appointment(appointment) do
      {:ok, _appointment} -> :ok
      :skip -> :ok
      {:error, reason} -> log_and_ok("upsert", appointment, reason)
    end
  end

  defp run("delete", appointment) do
    case GoogleCalendar.delete_appointment_event(appointment) do
      :ok -> :ok
      :skip -> :ok
      {:error, reason} -> log_and_ok("delete", appointment, reason)
    end
  end

  # Swallow Google errors (return :ok) so a dead connection doesn't churn
  # retries forever — the manual meeting_url fallback already covers the user.
  defp log_and_ok(action, appointment, reason) do
    Logger.warning(
      "[CalendarSync] #{action} failed for appointment ##{appointment.id}: #{inspect(reason)}"
    )

    :ok
  end
end
