defmodule Mix.Tasks.Research.Ingest do
  @shortdoc "Offline batch: run crawled studies through the extractor /analyze + store per condition"

  @moduledoc """
  **The one-shot, offline ingestion runner for the nutritionist research search.**

  The nutritionist-facing search (`/nutritionist/research`) is served **entirely
  from the database** — it never calls the `mehungry_extractor`. The extractor is
  needed **only here**, during ingestion: this task walks the conditions, sends
  each condition's crawled studies to the extractor's `POST /analyze` in batches,
  and persists the result (`Mehungry.Literature.store_analysis_response/1` — claims
  **and**, for open-access papers, the full-text `sections` outline). Run it once
  while the extractor is reachable; afterwards the digested research is available
  per condition **forever, offline**.

  It reuses the exact path the admin "Analyze selected" button uses
  (`:extractor_client` seam → `store_analysis_response/1`), so there is no second
  copy of the ingest logic.

      mix research.ingest                      # every condition, analyze studies not yet analyzed
      mix research.ingest "Ulcerative Colitis" # just one condition (name, case-insensitive)
      mix research.ingest --crawl              # PubMed-crawl each condition first, then analyze
      mix research.ingest --force              # re-analyze even already-analyzed studies
                                               #   (use to backfill `sections` onto old analyses)
      mix research.ingest --batch 100          # extractor batch size (default 200, the API max)

  Idempotent + resumable: by default a study already analyzed is skipped, and
  studies a prior analysis flagged non-open-access (unusable) are always skipped
  (re-analyzing them can't produce full text). Network/extractor failures are
  reported per batch and abort the run (so you can fix the connection and re-run —
  already-stored work is kept).

  The crawl step (`--crawl`) talks to **NCBI/PubMed**, not the extractor; omit it
  if the studies are already in the DB.
  """

  use Mix.Task

  alias Mehungry.Health
  alias Mehungry.Literature.ResearchIngestion

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, names, _} =
      OptionParser.parse(args,
        strict: [crawl: :boolean, force: :boolean, batch: :integer, condition: :string]
      )

    batch = min(opts[:batch] || 200, 200)
    name_filter = opts[:condition] || List.first(names)

    conditions = conditions(name_filter)

    if conditions == [] do
      Mix.shell().error("No matching conditions.")
    else
      Mix.shell().info(
        "Ingesting #{length(conditions)} condition(s) · batch=#{batch} · " <>
          "crawl=#{!!opts[:crawl]} · force=#{!!opts[:force]}"
      )

      totals =
        Enum.reduce(conditions, ResearchIngestion.zero_counts(), fn condition, acc ->
          ResearchIngestion.merge_counts(acc, ingest_condition(condition, batch, opts))
        end)

      Mix.shell().info("")
      Mix.shell().info("── Done ──────────────────────────────────────────")
      Mix.shell().info(summary("TOTAL", totals))
      Mix.shell().info("Nutritionist search now serves these offline (no extractor needed).")
    end
  end

  # ── One condition ────────────────────────────────────────────────────────────

  # Thin shell wrapper over the shared ingest core (reused by the admin worker).
  defp ingest_condition(condition, batch, opts) do
    Mix.shell().info("")
    Mix.shell().info("▸ #{condition.name} (##{condition.id})")

    if opts[:crawl], do: Mix.shell().info("  crawling PubMed…")

    case ResearchIngestion.analyze_condition(condition.id,
           crawl: opts[:crawl],
           force: opts[:force],
           batch: batch
         ) do
      {:ok, counts, target_count} ->
        Mix.shell().info("  #{target_count} to analyze → #{summary("stored", counts)}")
        counts

      {:error, reason} ->
        Mix.shell().error("  ! extractor call failed: #{inspect(reason)}")
        Mix.raise("Ingestion aborted — fix the extractor connection and re-run (stored work kept).")
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  defp conditions(nil), do: Health.list_conditions()

  defp conditions(name) do
    term = name |> to_string() |> String.downcase()
    Enum.filter(Health.list_conditions(), &(String.downcase(&1.name) =~ term))
  end

  defp summary(label, %{inserted: i, updated: u, unchanged: n, skipped: s}),
    do: "#{label}: #{i} inserted, #{u} updated, #{n} unchanged, #{s} skipped"
end
