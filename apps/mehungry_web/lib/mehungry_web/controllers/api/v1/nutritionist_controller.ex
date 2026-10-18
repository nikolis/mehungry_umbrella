defmodule MehungryWeb.Api.V1.NutritionistController do
  @moduledoc """
  Nutritionist portal (spec §14, phase 2) — clients, a client's calendar,
  appointments, and sent invitations. Gated to the `"pro"` tier by
  `MehungryWeb.Api.RequireNutritionistPlug`. Backed by `Professionals` + `History`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.History
  alias Mehungry.Professionals
  alias MehungryWeb.Api.V1.MealJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def clients(conn, _params) do
    clients = Professionals.list_clients(uid(conn))
    json(conn, data(Enum.map(clients, &client_json/1)))
  end

  def client(conn, %{"id" => client_id}) do
    with {:ok, assignment} <- fetch_client(conn, client_id) do
      json(conn, data(client_json(assignment)))
    end
  end

  def client_meals(conn, %{"id" => client_id} = params) do
    with {:ok, _assignment} <- fetch_client(conn, client_id),
         {:ok, start_date} <- parse_date(params["start"]),
         {:ok, end_date} <- parse_date(params["end"]) do
      meals = History.list_user_meals_in_range(to_int(client_id), start_date, end_date)
      json(conn, MealJSON.range(meals, start_date, end_date))
    end
  end

  def appointments(conn, params) do
    {start_dt, end_dt} = appointment_range(params)
    appointments = Professionals.list_appointments_for_professional(uid(conn), start_dt, end_dt)
    json(conn, data(Enum.map(appointments, &appointment_json/1)))
  end

  def invitations(conn, _params) do
    invitations = Professionals.list_sent_invitations(uid(conn))
    json(conn, data(Enum.map(invitations, &invitation_json/1)))
  end

  def invite(conn, %{"email" => email} = params) do
    with {:ok, inv} <- Professionals.invite_client(uid(conn), email, params["message"]) do
      conn |> put_status(:created) |> json(data(invitation_json(inv)))
    end
  end

  def invite(conn, _params), do: {:error, :bad_request}

  # ── serializers ────────────────────────────────────────────────────────

  defp client_json(assignment) do
    client = assoc(assignment.client)
    profile = client && assoc(client.user_profile)

    %{
      client_id: assignment.client_id,
      alias: (profile && profile.alias) || (client && (client.name || client.email))
    }
  end

  defp appointment_json(appt) do
    %{
      id: appt.id,
      title: appt.title,
      status: appt.status,
      scheduled_at: naive(appt.scheduled_at),
      ends_at: naive(appt.ends_at),
      meeting_url: appt.meeting_url,
      client_id: appt.client_id
    }
  end

  defp invitation_json(inv) do
    %{id: inv.id, status: inv.status, message: inv.message, client_id: inv.client_id}
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp fetch_client(conn, client_id) do
    cid = to_int(client_id)

    case Enum.find(Professionals.list_clients(uid(conn)), &(&1.client_id == cid)) do
      nil -> {:error, :not_found}
      assignment -> {:ok, assignment}
    end
  end

  defp appointment_range(params) do
    start_dt =
      case parse_date(params["start"]) do
        {:ok, d} -> NaiveDateTime.new!(d, ~T[00:00:00])
        _ -> NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 86400, :second)
      end

    end_dt =
      case parse_date(params["end"]) do
        {:ok, d} -> NaiveDateTime.new!(d, ~T[23:59:59])
        _ -> NaiveDateTime.add(NaiveDateTime.utc_now(), 90 * 86400, :second)
      end

    {NaiveDateTime.truncate(start_dt, :second), NaiveDateTime.truncate(end_dt, :second)}
  end

  defp parse_date(nil), do: {:error, :bad_request}

  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, :bad_request}
    end
  end

  defp assoc(%Ecto.Association.NotLoaded{}), do: nil
  defp assoc(value), do: value

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
