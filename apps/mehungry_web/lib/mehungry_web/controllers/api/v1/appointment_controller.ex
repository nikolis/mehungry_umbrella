defmodule MehungryWeb.Api.V1.AppointmentController do
  @moduledoc """
  Client-side appointments (spec §18) — list/show the client's own appointments,
  book one, and cancel one (tiered refund). Mirrors the shared
  `AppointmentBookingComponent` + the hub's cancel flow; delegates to
  `Mehungry.Professionals`. 🔒 — valid bearer token required; not pro-gated.
  """
  use MehungryWeb, :controller
  use MehungryWeb, :verified_routes

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.ObanWorkers.AppointmentMailerWorker
  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile
  alias MehungryWeb.Api.V1.NutritionistJSON, as: JSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, _params) do
    appointments = Professionals.list_appointments_for_client(uid(conn))
    now = now()
    profiles = profiles_by_id(Enum.map(appointments, & &1.professional_id))

    json(conn, data(Enum.map(appointments, &JSON.appointment(&1, profiles[&1.professional_id], now))))
  end

  def show(conn, %{"id" => id}) do
    with {:ok, appt} <- fetch(conn, id) do
      profile = Professionals.get_professional_profile(appt.professional_id)
      json(conn, data(JSON.appointment(appt, profile, now())))
    end
  end

  def create(conn, %{"professional_id" => professional_id, "scheduled_at" => scheduled_at} = params) do
    user = conn.assigns.current_user

    with {:ok, slot} <- parse_utc(scheduled_at),
         {:ok, pro_id} <- parse_id(professional_id),
         %ProfessionalProfile{} = profile <- Professionals.get_professional_profile(pro_id) do
      opts = [
        professional_service_id: params["service_id"],
        title: params["title"],
        notes: params["notes"],
        success_url: params["success_url"],
        cancel_url: params["cancel_url"]
      ]

      case Professionals.request_appointment(pro_id, user.id, slot, opts) do
        {:ok, appt, checkout_url} ->
          render_created(conn, appt, profile, checkout_url)

        {:ok, appt} ->
          notify_requested(appt, profile, user)
          render_created(conn, appt, profile, nil)

        {:error, _reason} = error ->
          error
      end
    else
      # A valid-format id for a professional with no profile → 404 (not a
      # misleading "slot unavailable"); a malformed id / timestamp → 400.
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  def cancel(conn, %{"id" => id}) do
    with {:ok, appt} <- fetch(conn, id),
         :ok <- ensure_cancellable(appt) do
      user = conn.assigns.current_user
      # Compute the refund *before* cancelling — the payment status changes after.
      refund = Professionals.client_cancellation_refund_cents(appt)

      with {:ok, cancelled} <- Professionals.cancel_appointment(appt) do
        AppointmentMailerWorker.enqueue("cancelled_by_client", appt.id, %{
          client_name: user.name || user.email,
          cta_url: url(~p"/nutritionist/appointments")
        })

        json(conn, data(%{id: cancelled.id, status: cancelled.status, refund_cents: refund}))
      end
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  defp render_created(conn, appt, profile, checkout_url) do
    conn
    |> put_status(:created)
    |> json(data(%{appointment: JSON.appointment(appt, profile, now()), checkout_url: checkout_url}))
  end

  defp notify_requested(appt, profile, user) do
    AppointmentMailerWorker.enqueue("requested", appt.id, %{
      professional_name: profile && profile.display_name,
      client_name: user.name || user.email,
      cta_url: url(~p"/nutritionist/appointments")
    })
  end

  defp fetch(conn, id) do
    case Professionals.get_appointment_for_client(uid(conn), to_int(id)) do
      nil -> {:error, :not_found}
      appt -> {:ok, appt}
    end
  end

  defp ensure_cancellable(appt) do
    if appt.status in ["requested", "accepted"] and
         NaiveDateTime.compare(appt.scheduled_at, now()) == :gt,
       do: :ok,
       else: {:error, :not_cancellable}
  end

  defp profiles_by_id(ids) do
    ids
    |> Enum.uniq()
    |> Map.new(fn id -> {id, Professionals.get_professional_profile(id)} end)
  end

  defp parse_id(value) do
    case to_int(value) do
      nil -> {:error, :bad_request}
      id -> {:ok, id}
    end
  end

  defp parse_utc(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> {:ok, DateTime.to_naive(dt) |> NaiveDateTime.truncate(:second)}
      _ -> {:error, :bad_request}
    end
  end

  defp parse_utc(_), do: {:error, :bad_request}

  defp now, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  defp uid(conn), do: conn.assigns.current_user.id
  defp to_int(v) when is_integer(v), do: v

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp to_int(_), do: nil
end
