defmodule Mix.Tasks.Gi.Verify do
  @shortdoc "Parse the published GI Tables PDF into an internal verification oracle"

  @moduledoc """
  **Internal verification tool — not an ingest path.** Parses a *published*
  International Tables of Glycemic Index PDF (`studies/SupplementalTable{1,2}.pdf`)
  into structured reference rows and reports coverage stats, so the path-B
  re-derivation can be checked against the published values *we never ship*. See
  `docs/science/glycemic_index_licensing.md`.

      mix gi.verify                                   # defaults to studies/SupplementalTable1.pdf
      mix gi.verify studies/SupplementalTable2.pdf --table table2
      mix gi.verify studies/SupplementalTable1.pdf --out /tmp/gi_ref.json

  Options:

    * `--table` — `table1` (default) | `table2`; else inferred from the filename.
    * `--out`   — write the parsed rows as JSON here (default: none, summary only).
    * `--sample` — print N sample rows (default 8).

  Requires `pdftotext` (poppler-utils) on `PATH`. Reads git-ignored `studies/` PDFs;
  never commit them and never ingest the output as served data.
  """

  use Mix.Task

  alias Mehungry.FoodData.GlycemicIndex.PdfReferenceParser

  @default_pdf "studies/SupplementalTable1.pdf"

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} =
      OptionParser.parse(args, strict: [table: :string, out: :string, sample: :integer])

    path = List.first(paths) || @default_pdf
    table = opts[:table] || infer_table(path)

    case PdfReferenceParser.parse(path, table: table) do
      {:ok, rows} ->
        report(rows, path, table, opts)
        maybe_write(rows, opts[:out])

      {:error, :pdftotext_missing} ->
        Mix.raise("`pdftotext` not found on PATH — install poppler-utils to run gi.verify.")

      {:error, reason} ->
        Mix.raise("Failed to parse #{path}: #{inspect(reason)}")
    end
  end

  defp report(rows, path, table, opts) do
    total = length(rows)
    unpublished = Enum.count(rows, & &1.unpublished)
    with_gi = Enum.count(rows, &(&1.gi_value != nil))
    named = Enum.count(rows, &(&1.food_item not in [nil, ""]))

    shell = Mix.shell()
    shell.info("Parsed #{path} (#{table})")
    shell.info("  rows:            #{total}")
    shell.info("  with GI value:   #{with_gi}  (#{pct(with_gi, total)}%)")
    shell.info("  with food name:  #{named}  (#{pct(named, total)}%)")
    shell.info("  unpublished (UO): #{unpublished}  (#{pct(unpublished, total)}%) — un-re-derivable")
    shell.info("  cited (re-derivable ceiling): #{total - unpublished}  (#{pct(total - unpublished, total)}%)")

    shell.info("  categories: #{rows |> Enum.map(& &1.category) |> Enum.uniq() |> length()}")

    shell.info("\n  sample rows:")
    rows |> Enum.take(opts[:sample] || 8) |> Enum.each(&shell.info("    " <> summarize(&1)))
  end

  defp summarize(r) do
    "##{r.food_number} [#{r.category}] #{r.food_item || "?"} — GI #{r.gi_value}±#{r.gi_sem} " <>
      "(#{r.country}, #{r.year}) ref=#{r.ref_code}#{if r.unpublished, do: " UO", else: ""}"
  end

  defp maybe_write(_rows, nil), do: :ok

  defp maybe_write(rows, out) do
    File.write!(out, Jason.encode!(rows, pretty: true))
    Mix.shell().info("\nWrote #{length(rows)} rows → #{out}")
  end

  defp infer_table(path) do
    if path |> Path.basename() |> String.downcase() =~ "table2", do: "table2", else: "table1"
  end

  defp pct(_n, 0), do: 0
  defp pct(n, total), do: Float.round(n * 100 / total, 1)
end
