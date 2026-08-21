defmodule MehungryWeb.Api.LocalAi.GiCandidatesController do
  @moduledoc """
  Receives **Glycemic Index** findings the local-AI service extracted from a study's
  full text and persists them as review-gated candidates (path B — see
  `docs/science/glycemic_index_licensing.md`). Each finding is fanned across the
  `FoundementalFoodSpecies` the study links to (`Food.record_extracted_gi/3`), the
  domain association the local service is kept ignorant of. Nothing auto-promotes.
  """

  use MehungryWeb, :controller

  alias Mehungry.{Food, Literature}

  def create(conn, %{"candidates" => candidates}) when is_list(candidates) do
    written = Enum.reduce(candidates, 0, fn c, acc -> acc + persist(c) end)
    json(conn, %{written: written})
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "missing required field: candidates (list)"})
  end

  defp persist(%{"study_id" => study_id, "gi_value" => gi_value} = c)
       when not is_nil(study_id) and not is_nil(gi_value) do
    finding = %{
      gi_value: gi_value,
      gi_sem: c["gi_sem"],
      reference_food: c["reference_food"],
      sample_size: c["sample_size"],
      country: c["country"],
      year: c["year"],
      analytical_method: c["analytical_method"],
      iso_method: c["iso_method"] || false,
      score: c["score"],
      raw_span: c["raw_span"],
      extraction_method: c["extraction_method"] || "automated"
    }

    Food.record_extracted_gi(study_id, [finding], Literature.species_ids_for_study(study_id))
  end

  defp persist(_invalid), do: 0
end
