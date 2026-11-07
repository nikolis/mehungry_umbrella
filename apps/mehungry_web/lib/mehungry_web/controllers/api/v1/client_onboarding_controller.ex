defmodule MehungryWeb.Api.V1.ClientOnboardingController do
  @moduledoc """
  The per-nutritionist onboarding questionnaire a client fills (spec §18) —
  mirrors `MehungryWeb.ClientOnboardingLive`. Keyed by `:professional_id` (not the
  assignment): gated on the nutritionist having opened a `ProfessionalClient` file
  for the user (`get_client_record_by_user/2`; `404` if none). Answers persist
  against that file (`subject_type: "professional_client"`) and surface to the
  nutritionist on the client file. Prompts/options localize via `Accept-Language`
  (resolved by `SetLocale` into `conn.assigns.content_locale`). 🔒.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Onboarding
  alias Mehungry.Professionals
  alias MehungryWeb.Api.V1.NutritionistJSON, as: JSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def show(conn, %{"professional_id" => professional_id}) do
    with {:ok, record, pro_id} <- fetch_record(conn, professional_id),
         :ok <- require_consent(conn) do
      json(conn, data(%{questions: questions_payload(pro_id, record, conn)}))
    end
  end

  def update(conn, %{"professional_id" => professional_id} = params) do
    with {:ok, record, pro_id} <- fetch_record(conn, professional_id),
         :ok <- require_consent(conn) do
      questions = active_questions(pro_id)
      answers = Map.get(params, "answers", %{})
      Onboarding.upsert_answers("professional_client", record.id, answers, questions)
      json(conn, data(%{questions: questions_payload(pro_id, record, conn)}))
    end
  end

  # ── helpers ──────────────────────────────────────────────────────────────────

  # The questionnaire returns/collects the client's health answers, so it is gated
  # on an active Art. 9 consent (checked after the client-file 404 so "no
  # relationship" stays a 404, not a misleading 403).
  defp require_consent(conn) do
    if Professionals.clinical_consent_granted?(uid(conn)),
      do: :ok,
      else: {:error, :consent_required}
  end

  defp fetch_record(conn, professional_id) do
    with pro_id when is_integer(pro_id) <- to_int(professional_id),
         %{} = record <- Professionals.get_client_record_by_user(pro_id, uid(conn)) do
      {:ok, record, pro_id}
    else
      _ -> {:error, :not_found}
    end
  end

  defp questions_payload(professional_id, record, conn) do
    questions = active_questions(professional_id)
    answers = Onboarding.get_answers("professional_client", record.id)
    locale = conn.assigns[:content_locale]

    Enum.map(questions, &JSON.question(&1, Map.get(answers, &1.id), locale))
  end

  defp active_questions(professional_id) do
    Onboarding.ensure_client_questions(professional_id)
    Onboarding.list_active_questions("client", professional_id)
  end

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
