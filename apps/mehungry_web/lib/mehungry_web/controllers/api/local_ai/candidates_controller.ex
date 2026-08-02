defmodule MehungryWeb.Api.LocalAi.CandidatesController do
  @moduledoc """
  Receives measurement findings extracted by the local-AI service and persists them
  as review-gated candidates. Each finding is fanned out across the
  `FoundementalFoodSpecies` the study is linked to (the domain association the local
  service is deliberately kept ignorant of), then upserted idempotently.
  """

  use MehungryWeb, :controller

  alias Mehungry.{Food, Literature}

  def create(conn, %{"candidates" => candidates}) when is_list(candidates) do
    written =
      Enum.reduce(candidates, 0, fn candidate, acc ->
        acc + persist(candidate)
      end)

    json(conn, %{written: written})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing required field: candidates (list)"})
  end

  defp persist(%{"study_id" => study_id, "compound_id" => compound_id, "value" => value, "unit" => unit} = c)
       when not is_nil(study_id) and not is_nil(compound_id) and not is_nil(value) and is_binary(unit) do
    Literature.species_ids_for_study(study_id)
    |> Enum.reduce(0, fn species_id, acc ->
      case Food.upsert_measurement_candidate(%{
             foundemental_species_id: species_id,
             compound_id: compound_id,
             study_id: study_id,
             value: value,
             unit: unit,
             preparation_method: c["preparation_method"],
             analytical_method: c["analytical_method"],
             score: c["score"],
             raw_span: c["raw_span"],
             extraction_method: c["extraction_method"] || "automated"
           }) do
        {:ok, _} -> acc + 1
        {:error, _} -> acc
      end
    end)
  end

  defp persist(_invalid), do: 0
end
