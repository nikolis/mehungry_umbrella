defmodule MehungryWeb.Api.LocalAi.FullTextController do
  @moduledoc """
  Receives one PMC fetch result from the local-AI service: stores the full text (when
  the paper was open-access) and always ledgers the fetch attempt so the study leaves
  the pending set.
  """

  use MehungryWeb, :controller

  alias Mehungry.Literature

  def create(conn, %{"study_id" => study_id} = params) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    pmcid = params["pmcid"]
    body = params["body"]

    if is_binary(body) and body != "" do
      {:ok, _} =
        Literature.upsert_full_text(%{
          study_id: study_id,
          pmcid: pmcid,
          source: params["source"] || "pmc_oa",
          body: body,
          retrieved_at: now
        })
    end

    {:ok, _} =
      Literature.record_pmc_attempt(%{
        study_id: study_id,
        pmcid: pmcid,
        outcome: params["outcome"] || "error",
        last_attempted_at: now
      })

    json(conn, %{ok: true})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing required field: study_id"})
  end
end
