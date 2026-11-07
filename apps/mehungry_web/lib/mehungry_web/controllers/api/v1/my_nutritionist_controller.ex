defmodule MehungryWeb.Api.V1.MyNutritionistController do
  @moduledoc """
  The client-facing "My nutritionist" hub (spec §18) — the connected-nutritionist
  payload, self-disconnect, the message thread, and the client's own progress
  chart. Mirrors `MehungryWeb.MyNutritionistLive.Index` (hub + embedded
  `MessagesComponent`) and the `/profile` "My progress" chart. All reads/writes
  delegate to `Mehungry.Professionals`. 🔒 — valid bearer token required; not
  pro-gated.

  "Who is my nutritionist" is the one-per-client `TutorClientAssignment`
  (`get_assignment_for_client/1`), **not** the clinical `ProfessionalClient` file.
  Consultation-note bodies/to-dos are never exposed here — only note-derived
  *measurements*, via `progress/2`.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Professionals
  alias Mehungry.Professionals.ProfessionalProfile
  alias MehungryWeb.Api.V1.NutritionistJSON, as: JSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def show(conn, _params) do
    uid = uid(conn)
    assignment = Professionals.get_assignment_for_client(uid)
    invitations = Professionals.list_pending_invitations_for_client(uid)

    # The assignment preloads only the professional *user*, so the profile (slug,
    # photo, …) is fetched separately; batch-cache across the assignment + invites.
    profiles =
      profiles_by_id([assignment && assignment.professional_id | Enum.map(invitations, & &1.professional_id)])

    # An assignment means connected — even if the nutritionist has no
    # `ProfessionalProfile` row yet (mirrors the web hub's "connected, no public
    # profile" state), in which case the preview falls back to the professional
    # `User` the assignment preloads.
    {connected, nutritionist} =
      case assignment do
        nil -> {false, nil}
        _ -> {true, hub_preview(assignment, profiles[assignment.professional_id])}
      end

    json(
      conn,
      data(%{
        connected: connected,
        nutritionist: nutritionist,
        unread_messages: Professionals.count_unread_messages_for(uid),
        pending_invitations:
          Enum.map(invitations, &JSON.invitation(&1, profiles[&1.professional_id])),
        consent: JSON.consent(Professionals.current_clinical_consent(uid))
      })
    )
  end

  def disconnect(conn, _params) do
    with {:ok, _assignment} <- Professionals.unassign_nutritionist(uid(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  def messages(conn, _params) do
    with {:ok, assignment} <- assignment(conn) do
      profile = Professionals.get_professional_profile(assignment.professional_id)
      messages = Professionals.list_messages(assignment.professional_id, uid(conn))

      json(
        conn,
        data(%{
          nutritionist: %{
            professional_id: assignment.professional_id,
            display_name: profile && profile.display_name
          },
          messages: Enum.map(messages, &JSON.message(&1, uid(conn)))
        })
      )
    end
  end

  def send_message(conn, %{"body" => body}) when is_binary(body) and body != "" do
    with {:ok, assignment} <- assignment(conn),
         {:ok, message} <-
           Professionals.send_message(assignment.professional_id, uid(conn), uid(conn), body) do
      conn |> put_status(:created) |> json(data(JSON.message(message, uid(conn))))
    end
  end

  def send_message(_conn, _params), do: {:error, :bad_request}

  def read_messages(conn, _params) do
    with {:ok, assignment} <- assignment(conn) do
      Professionals.mark_thread_read(assignment.professional_id, uid(conn), uid(conn))
      send_resp(conn, :no_content, "")
    end
  end

  def progress(conn, _params) do
    uid = uid(conn)

    with :ok <- require_consent(uid) do
      json(
        conn,
        data(
          JSON.progress(
            Professionals.measurement_history_for_user(uid),
            Professionals.measurement_context_for_user(uid)
          )
        )
      )
    end
  end

  # ── Clinical-data consent (GDPR Art. 9) ───────────────────────────────────────

  def grant_consent(conn, params) do
    with {:ok, consent} <-
           Professionals.grant_clinical_consent(uid(conn), Map.get(params, "version")) do
      json(conn, data(%{consent: JSON.consent(consent)}))
    end
  end

  def withdraw_consent(conn, _params) do
    Professionals.withdraw_clinical_consent(uid(conn))
    send_resp(conn, :no_content, "")
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  # Gate the health-data reads/writes on an active Art. 9 consent (defense in
  # depth — a compliant client already gates its UI on the hub `consent` field).
  defp require_consent(user_id) do
    if Professionals.clinical_consent_granted?(user_id), do: :ok, else: {:error, :consent_required}
  end

  defp hub_preview(_assignment, %ProfessionalProfile{} = profile),
    do: JSON.hub_nutritionist(profile, payments_enabled?(profile))

  defp hub_preview(assignment, _no_profile),
    do: JSON.hub_nutritionist(assignment.professional, false)

  defp assignment(conn) do
    case Professionals.get_assignment_for_client(uid(conn)) do
      nil -> {:error, :not_found}
      assignment -> {:ok, assignment}
    end
  end

  defp profiles_by_id(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn id -> {id, Professionals.get_professional_profile(id)} end)
  end

  defp payments_enabled?(profile),
    do: Professionals.consultation_payments_enabled?() and ProfessionalProfile.payable?(profile)

  defp uid(conn), do: conn.assigns.current_user.id
end
