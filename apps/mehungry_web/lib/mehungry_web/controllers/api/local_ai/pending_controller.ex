defmodule MehungryWeb.Api.LocalAi.PendingController do
  @moduledoc """
  Serves studies that still need PMC fetch + measurement extraction to the local-AI
  service. A study leaves this set once the service posts back a fetch result (which
  ledgers an attempt), guaranteeing the local batch terminates.
  """

  use MehungryWeb, :controller

  alias Mehungry.{Food, Literature}

  def index(conn, params) do
    limit = parse_int(params["limit"], 25)

    studies =
      limit
      |> Literature.list_unfetched_studies()
      |> Enum.map(&study_payload/1)

    %{processed: processed, total: total} = Literature.pmc_fetch_progress()

    json(conn, %{studies: studies, total: max(total - processed, 0)})
  end

  defp study_payload(study) do
    compounds =
      study.id
      |> Literature.compound_ids_for_study()
      |> Food.get_compounds_by_ids()
      |> Enum.map(fn c -> %{id: c.id, name: c.name, synonyms: c.synonyms || []} end)

    %{
      study_id: study.id,
      pmid: study.pmid,
      compounds: compounds,
      extract_gi: Literature.gi_discovered?(study.id)
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
