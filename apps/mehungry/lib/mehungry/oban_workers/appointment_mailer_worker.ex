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

  alias Mehungry.Accounts
  alias Mehungry.Professionals
  alias Mehungry.Accounts.UserNotifier
  alias Mehungry.Repo

  @doc """
  Enqueue an appointment email. `kind` is `"requested"` | `"accepted"` |
  `"declined"` | `"cancelled_by_client"` (→ notifies the nutritionist) |
  `"cancelled_by_professional"` (→ notifies the client, full-refund note).
  """
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

    # Each email is localized to the language of its *recipient* — the
    # nutritionist for requests/client-cancellations, the client otherwise.
    result =
      case kind do
        "requested" ->
          locale = user_locale(appointment.professional)
          UserNotifier.deliver_appointment_requested(appointment, client_name, cta_url, locale)

        "accepted" ->
          locale = user_locale(appointment.client)
          UserNotifier.deliver_appointment_accepted(appointment, professional_name, cta_url, locale)

        "declined" ->
          locale = user_locale(appointment.client)
          UserNotifier.deliver_appointment_declined(appointment, professional_name, cta_url, locale)

        "cancelled_by_client" ->
          locale = user_locale(appointment.professional)
          UserNotifier.deliver_appointment_cancelled_by_client(appointment, client_name, cta_url, locale)

        "cancelled_by_professional" ->
          locale = user_locale(appointment.client)
          UserNotifier.deliver_appointment_cancelled_by_professional(
            appointment,
            professional_name,
            cta_url,
            locale
          )
      end

    case result do
      {:ok, _email} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp client_email(%{client: %{email: email}}), do: email
  defp client_email(_), do: "there"

  defp user_locale(%{id: id}) when not is_nil(id), do: Accounts.get_user_language(id)
  defp user_locale(_), do: "en"
end
