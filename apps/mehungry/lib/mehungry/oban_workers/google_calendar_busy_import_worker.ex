defmodule Mehungry.ObanWorkers.GoogleCalendarBusyImportWorker do
  @moduledoc """
  Imports connected nutritionists' Google Calendar busy intervals into the local
  `professional_calendar_busy` cache the slot engine reads, so the public booking
  page respects each nutritionist's personal calendar without a live Google call.

  Runs two ways:

    * **cron** (no args) — sweeps every connected account;
    * **targeted** (`enqueue/1`) — refreshes one account right after it connects.

  Per-account failures are logged but never fail the job, so one dead connection
  can't churn retries for the healthy ones.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Mehungry.Professionals
  alias Mehungry.Professionals.GoogleCalendar

  @doc "Enqueue a busy-import for a single professional (e.g. just after connect)."
  def enqueue(professional_id) do
    %{"professional_id" => professional_id}
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"professional_id" => professional_id}}) do
    case Professionals.get_google_account(professional_id) do
      nil -> :ok
      account -> import_one(account)
    end
  end

  def perform(%Oban.Job{}) do
    Professionals.list_google_accounts()
    |> Enum.each(&import_one/1)

    :ok
  end

  defp import_one(account) do
    case GoogleCalendar.import_busy(account) do
      {:ok, count} ->
        Logger.info("[CalendarBusy] imported #{count} intervals for ##{account.professional_id}")

      :skip ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[CalendarBusy] import failed for ##{account.professional_id}: #{inspect(reason)}"
        )
    end
  end
end
