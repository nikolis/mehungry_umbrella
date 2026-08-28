defmodule Mehungry.ObanWorkers.AppointmentMailerWorker do
  @moduledoc """
  Sends appointment-related emails off the request cycle on the `:mailers`
  queue. Enqueued when a client requests an appointment and when a nutritionist
  accepts/declines it. Display strings (`professional_name`, `client_name`) and
  the CTA URL are supplied by the web caller (built from verified routes) so the
  core app never has to know web routing. The acceptance email carries an `.ics`
  calendar invite.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Mehungry.Professionals
  alias Mehungry.Accounts.UserNotifier
  alias Mehungry.Repo

  @doc "Enqueue an appointment email. `kind` is \"requested\" | \"accepted\" | \"declined\"."
  def enqueue(kind, appointment_id, opts \\ %{}) do
    %{
      "kind" => kind,
      "appointment_id" => appointment_id,
      "professional_name" => opts[:professional_name],
      "client_name" => opts[:client_name],
      "cta_url" => opts[:cta_url]
    }
    |> new()
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"appointment_id" => id, "kind" => kind} = args}) do
    appointment =
      id
      |> Professionals.get_appointment!()
      |> Repo.preload([:professional, :client])

    professional_name = args["professional_name"] || "Your nutritionist"
    client_name = args["client_name"] || client_email(appointment)
    cta_url = args["cta_url"] || "https://www.m3hungry.com/home"

    result =
      case kind do
        "requested" ->
          UserNotifier.deliver_appointment_requested(appointment, client_name, cta_url)

        "accepted" ->
          UserNotifier.deliver_appointment_accepted(appointment, professional_name, cta_url)

        "declined" ->
          UserNotifier.deliver_appointment_declined(appointment, professional_name, cta_url)
      end

    case result do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp client_email(%{client: %{email: email}}), do: email
  defp client_email(_), do: "there"
end
