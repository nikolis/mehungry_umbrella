defmodule Mix.Tasks.Gi.Diff do
  @shortdoc "Diff our re-derived GI values against the published PDF oracle"

  @moduledoc """
  **Internal verification tool — not an ingest path.** Compares the GI values we
  re-derived from primary literature (path B) against the *published* values parsed from
  a git-ignored International Tables PDF, reporting coverage + agreement with a tolerance
  band and a "divergence to investigate" bucket. See
  `docs/science/glycemic_index_licensing.md`.

      mix gi.diff                                    # oracle = studies/SupplementalTable1.pdf
      mix gi.diff studies/SupplementalTable2.pdf --table table2
      mix gi.diff --tolerance 8 --out /tmp/gi_divergences.json

  Options:

    * `--table`      — `table1` (default) | `table2`; else inferred from the filename.
    * `--tolerance`  — GI-unit band for "agree" (default 10).
    * `--similarity` — jaro floor for food→species matching (default 0.82).
    * `--statuses`   — comma list of candidate states to count as re-derived
      (default `pending,promoted`).
    * `--out`        — write the divergence + orphan detail as JSON here.

  Requires `pdftotext` (poppler-utils). The compilation PDF is used **only** as a
  measuring stick — never ingested-as-served.
  """

  use Mix.Task

  alias Mehungry.Food
  alias Mehungry.FoodData.GlycemicIndex.{OracleDiff, PdfReferenceParser}

  @requirements ["app.start"]

  @default_pdf "studies/SupplementalTable1.pdf"

  @impl true
  def run(args) do
    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [
          table: :string,
          tolerance: :float,
          similarity: :float,
          statuses: :string,
          out: :string
        ]
      )

    path = List.first(paths) || @default_pdf
    table = opts[:table] || infer_table(path)

    case PdfReferenceParser.parse(path, table: table) do
      {:ok, oracle_rows} ->
        report = OracleDiff.compare(oracle_rows, rederived(opts), compare_opts(opts))
        print(report, path, opts)
        maybe_write(report, opts[:out])

      {:error, :pdftotext_missing} ->
        Mix.raise("`pdftotext` not found on PATH — install poppler-utils to run gi.diff.")

      {:error, reason} ->
        Mix.raise("Failed to parse #{path}: #{inspect(reason)}")
    end
  end

  defp rederived(opts) do
    case opts[:statuses] do
      nil -> Food.rederived_glycemic_by_species()
      s -> Food.rederived_glycemic_by_species(statuses: String.split(s, ","))
    end
  end

  defp compare_opts(opts) do
    []
    |> put(:tolerance, opts[:tolerance])
    |> put(:min_similarity, opts[:similarity])
  end

  defp put(kw, _k, nil), do: kw
  defp put(kw, k, v), do: Keyword.put(kw, k, v)

  defp print(r, path, opts) do
    shell = Mix.shell()
    shell.info("Oracle: #{path}  ·  tolerance ±#{opts[:tolerance] || 10} GI")
    shell.info("  oracle rows:        #{r.total_oracle}")
    shell.info("  unpublished (gaps): #{r.unpublished}  (un-re-derivable)")
    shell.info("  publishable:        #{r.publishable}")
    shell.info("  covered:            #{r.covered}  (#{r.coverage_pct}% of publishable)")
    shell.info("    · agree:          #{r.agree}  (#{r.agreement_pct}% of covered)")
    shell.info("    · diverge:        #{r.diverge}  ← investigate")
    shell.info("  uncovered:          #{r.uncovered}")
    shell.info("  orphan species:     #{length(r.orphan_species)}  (re-derived, no oracle match)")

    unless r.divergences == [] do
      shell.info("\n  top divergences (published vs ours):")

      r.divergences
      |> Enum.take(15)
      |> Enum.each(fn d ->
        shell.info(
          "    #{d.food} → #{d.species}: published #{d.oracle_gi} vs ours #{d.our_gi} (Δ#{d.delta})"
        )
      end)
    end
  end

  defp maybe_write(_report, nil), do: :ok

  defp maybe_write(report, out) do
    payload = Map.take(report, [:divergences, :orphan_species])
    File.write!(out, Jason.encode!(payload, pretty: true))
    Mix.shell().info("\nWrote divergences + orphans → #{out}")
  end

  defp infer_table(path) do
    if path |> Path.basename() |> String.downcase() =~ "table2", do: "table2", else: "table1"
  end
end
