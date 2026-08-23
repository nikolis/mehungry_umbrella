defmodule Mix.Tasks.LocalAi.Extract do
  @moduledoc """
  Pull studies needing processing from the deployed app, do PMC full-text fetch +
  parse + measurement extraction locally (Bumblebee QA on EXLA), and post the full
  text + measurement candidates back over REST.

      mix local_ai.extract --limit 200
      mix local_ai.extract --limit 50 --offset 0
      mix local_ai.extract --no-qa          # rule-based only, skip the model load

  Requires `LOCAL_AI_SERVER_URL` and `LOCAL_AI_API_TOKEN` (see config/runtime.exs).
  The QA model is **not** loaded at app boot; this task loads it once via
  `MehungryLocalAi.QA.ensure_started/0` (slow on first run — downloads the model).
  Pass `--no-qa` to skip the load and run the rule-based extractor only.
  """

  use Mix.Task

  alias MehungryLocalAi.{Client, Extractor, PMC}

  @shortdoc "Fetch + extract measurement candidates locally and post them to the server"

  @batch 25

  @impl true
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [limit: :integer, offset: :integer, qa: :boolean])

    limit = opts[:limit] || 100
    offset = opts[:offset] || 0

    {:ok, _} = Application.ensure_all_started(:mehungry_local_ai)

    # The QA model is off at boot; load it here unless --no-qa was passed (which runs
    # the rule-based extractor only). This is the explicit "flag to start" the serving.
    unless opts[:qa] == false do
      case MehungryLocalAi.QA.ensure_started() do
        :ok -> :ok
        {:error, reason} -> Mix.shell().error("QA failed to start: #{inspect(reason)} — falling back to rule-based extraction")
      end
    end

    Mix.shell().info("local_ai.extract: processing up to #{limit} studies (QA available? #{MehungryLocalAi.QA.available?()})")

    totals = loop(limit, offset, %{studies: 0, full_texts: 0, candidates: 0, gi_candidates: 0})

    Mix.shell().info(
      "done: processed #{totals.studies} studies, stored #{totals.full_texts} full texts, " <>
        "posted #{totals.candidates} measurement + #{totals.gi_candidates} GI candidates"
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

  defp process_study(%{study_id: study_id, pmid: pmid, compounds: compounds} = study, totals) do
    case PMC.fetch(pmid) do
      {:ok, result} ->
        Client.post_full_text(Map.put(result, :study_id, study_id))
        totals = bump(totals, :studies)
        totals = if result.outcome == "open_access", do: bump(totals, :full_texts), else: totals

        totals = extract_and_post(result, study_id, compounds, totals)
        gi_extract_and_post(result, study_id, study[:extract_gi] == true, totals)

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

  # GI extraction over the same full text, only for GI-discovered studies.
  defp gi_extract_and_post(%{outcome: "open_access", body: body}, study_id, true, totals)
       when is_binary(body) do
    candidates =
      body
      |> Extractor.gi_findings()
      |> Enum.map(&Map.put(&1, :study_id, study_id))

    case Client.post_gi_candidates(candidates) do
      {:ok, %{"written" => n}} -> bump(totals, :gi_candidates, n)
      {:ok, _} -> bump(totals, :gi_candidates, length(candidates))
      {:error, reason} ->
        Mix.shell().error("study #{study_id} GI candidate post failed: #{inspect(reason)}")
        totals
    end
  end

  defp gi_extract_and_post(_result, _study_id, _extract_gi, totals), do: totals

  defp bump(totals, key, by \\ 1), do: Map.update!(totals, key, &(&1 + by))
end
