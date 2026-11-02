defmodule Mehungry.ObanWorkers.AppointmentHoldExpiryWorker do
  @moduledoc """
  Cron sweep that releases consultation card-holds before Stripe silently voids
  them.

  A paid booking authorizes (holds) the client's card at request time and only
  captures it when the nutritionist accepts. Stripe voids an uncaptured
  PaymentIntent after ~7 days. If a nutritionist never responds, the hold would
  expire on Stripe's side while our appointment lingered as `requested` — the
  client's money stays reserved on their statement with no resolution.

  This worker auto-declines any still-`requested` booking whose authorized hold
  is older than ~6 days (`Professionals.expiring_authorized_appointments/1`),
  which cancels the PaymentIntent (releasing the hold) and marks the payment
  `canceled`. Runs hourly (`config/config.exs`); idempotent — once declined an
  appointment is no longer `requested` so it won't be picked up again.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Mehungry.Professionals

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    expiring = Professionals.expiring_authorized_appointments()

    Enum.each(expiring, fn appointment ->
      Professionals.decline_appointment(appointment)
    end)

    case length(expiring) do
      0 -> :ok
      n -> Logger.info("AppointmentHoldExpiryWorker: released #{n} expiring consultation hold(s)")
    end

    :ok
  end
end
