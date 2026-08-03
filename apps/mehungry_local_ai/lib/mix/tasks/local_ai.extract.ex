defmodule Mix.Tasks.LocalAi.Extract do
  @moduledoc """
  Pull studies needing processing from the deployed app, do PMC full-text fetch +
  parse + measurement extraction locally (Bumblebee QA on EXLA), and post the full
  text + measurement candidates back over REST.

      mix local_ai.extract --limit 200
      mix local_ai.extract --limit 50 --offset 0

  Requires `LOCAL_AI_SERVER_URL` and `LOCAL_AI_API_TOKEN` (see config/runtime.exs).
  Booting the app loads the QA model once (slow on first run — downloads the model).
  """

  use Mix.Task

  alias MehungryLocalAi.{Client, Extractor, PMC}

  @shortdoc "Fetch + extract measurement candidates locally and post them to the server"

  @batch 25

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [limit: :integer, offset: :integer])
    limit = opts[:limit] || 100
    offset = opts[:offset] || 0

    # Boots MehungryLocalAi.Application → loads the QA serving once.
    {:ok, _} = Application.ensure_all_started(:mehungry_local_ai)

    Mix.shell().info("local_ai.extract: processing up to #{limit} studies (QA available? #{MehungryLocalAi.QA.available?()})")

    totals = loop(limit, offset, %{studies: 0, full_texts: 0, candidates: 0})

    Mix.shell().info(
      "done: processed #{totals.studies} studies, stored #{totals.full_texts} full texts, posted #{totals.candidates} candidates"
    )
  end

  defp loop(remaining, _offset, totals) when remaining <= 0, do: totals

  defp loop(remaining, offset, totals) do
    take = min(remaining, @batch)

    case Client.pending(take, offset) do
      {:ok, %{studies: []}} ->
        totals

      {:ok, %{studies: studies}} ->
        new_totals = Enum.reduce(studies, totals, &process_study/2)
        loop(remaining - length(studies), offset, new_totals)

      {:error, reason} ->
        Mix.shell().error("pending fetch failed: #{inspect(reason)} — stopping")
        totals
    end
  end

  defp process_study(%{study_id: study_id, pmid: pmid, compounds: compounds}, totals) do
    case PMC.fetch(pmid) do
      {:ok, result} ->
        Client.post_full_text(Map.put(result, :study_id, study_id))
        totals = bump(totals, :studies)
        totals = if result.outcome == "open_access", do: bump(totals, :full_texts), else: totals
        extract_and_post(result, study_id, compounds, totals)

      {:error, reason} ->
        Mix.shell().error("study #{study_id} (pmid #{pmid}) fetch failed: #{inspect(reason)} — skipping")
        bump(totals, :studies)
    end
  end

  defp extract_and_post(%{outcome: "open_access", body: body}, study_id, compounds, totals)
       when is_binary(body) and compounds != [] do
    candidates =
      body
      |> Extractor.findings(compounds)
      |> Enum.map(&Map.put(&1, :study_id, study_id))

    case Client.post_candidates(candidates) do
      {:ok, %{"written" => n}} -> bump(totals, :candidates, n)
      {:ok, _} -> bump(totals, :candidates, length(candidates))
      {:error, reason} ->
        Mix.shell().error("study #{study_id} candidate post failed: #{inspect(reason)}")
        totals
    end
  end

  defp extract_and_post(_result, _study_id, _compounds, totals), do: totals

  defp bump(totals, key, by \\ 1), do: Map.update!(totals, key, &(&1 + by))
end
