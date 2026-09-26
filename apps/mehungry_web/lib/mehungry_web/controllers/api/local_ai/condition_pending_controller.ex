defmodule MehungryWeb.Api.LocalAi.ConditionPendingController do
  @moduledoc """
  Serves `(study, condition)` pairs — discovered by the reverse crawl — that still
  need phase-aware recommendation extraction to the offline Python service. A pair
  leaves this set once the service posts back (which ledgers an attempt), guaranteeing
  the batch terminates. Each pair carries the condition's disease states so the
  extractor knows which phases to classify findings into.
  """

  use MehungryWeb, :controller

  alias Mehungry.Health
  alias Mehungry.Health.ConditionRecCandidates

  def index(conn, params) do
    limit = parse_int(params["limit"], 25)

    pairs =
      limit
      |> ConditionRecCandidates.list_pending_extraction()
      |> Enum.map(&pair_payload/1)

    %{processed: processed, total: total} = ConditionRecCandidates.extraction_progress()

    json(conn, %{pairs: pairs, total: max(total - processed, 0)})
  end

  defp pair_payload(%{study_id: study_id, condition_id: condition_id, pmid: pmid}) do
    condition = Health.get_condition!(condition_id)

    states =
      condition_id
      |> Health.list_states_for_condition()
      |> Enum.map(fn s -> %{id: s.id, slug: s.slug, name: s.name, description: s.description} end)

    %{
      study_id: study_id,
      pmid: pmid,
      condition: %{
        id: condition.id,
        name: condition.name,
        synonyms: condition.synonyms || []
      },
      states: states
    }
  end

  defp parse_int(nil, default), do: default

  defp parse_int(v, default) do
    case Integer.parse(to_string(v)) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end
end
