defmodule MehungryWeb.Api.LocalAi.ConditionRecCandidatesController do
  @moduledoc """
  Receives phase-aware recommendation findings extracted from a condition's
  literature by the offline Python service and persists them as review-gated
  candidates. Each request is for one `(study, condition)` pair: the pair's
  extraction attempt is ledgered (so it leaves the pending set even when zero
  findings were produced), and each finding is upserted idempotently.

  Expected body:

      {
        "study_id": 123,
        "condition_id": 45,
        "findings": [
          {"raw_term": "insoluble fiber", "target_kind": "nutrient",
           "direction": "avoid", "condition_state_slug": "active_flare",
           "severity": "high", "confidence": 0.82, "evidence_snippet": "..."}
        ]
      }
  """

  use MehungryWeb, :controller

  alias Mehungry.Health.ConditionRecCandidates

  def create(conn, %{"study_id" => study_id, "condition_id" => condition_id} = params)
      when not is_nil(study_id) and not is_nil(condition_id) do
    findings = params["findings"] || []

    written =
      Enum.reduce(findings, 0, fn finding, acc ->
        attrs =
          finding
          |> Map.put("study_id", study_id)
          |> Map.put("condition_id", condition_id)

        case ConditionRecCandidates.upsert_candidate(attrs) do
          {:ok, _} -> acc + 1
          {:error, _} -> acc
        end
      end)

    # Ledger the attempt so this pair leaves the pending set (even with 0 findings).
    ConditionRecCandidates.record_extraction_attempt(%{
      "study_id" => study_id,
      "condition_id" => condition_id,
      "candidates_found" => written
    })

    json(conn, %{written: written})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing required fields: study_id, condition_id"})
  end
end
