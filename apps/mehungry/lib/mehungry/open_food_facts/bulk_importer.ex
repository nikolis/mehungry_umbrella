defmodule Mehungry.OpenFoodFacts.BulkImporter do
  @moduledoc """
  One-time bulk import of the Open Food Facts JSONL dump (~10 GB gzipped,
  ~4M products) filtered to European countries.

  Runs synchronously (mix task / release command / iex), NOT as an Oban job:
  a multi-hour job would restart from zero on retry and pin a queue slot
  across deploys. Weekly freshness afterwards comes from
  `Mehungry.ObanWorkers.OffDeltaSyncWorker`.

  Streaming is constant-memory: gzip is inflated on the fly, lines are
  parsed one at a time and upserted in chunks of #{500}.

      BulkImporter.run(path: "/data/openfoodfacts-products.jsonl.gz")
      BulkImporter.run(download: true)
      BulkImporter.run(path: dump, resume_from: 1_240_000)
  """

  require Logger

  alias Mehungry.FoodProducts
  alias Mehungry.OpenFoodFacts.ProductParser

  @chunk_size 500
  @progress_every 10_000

  @doc """
  Runs the import. Options:

  - `path:` — local dump file (`.jsonl` or `.jsonl.gz`); skips downloading
  - `download: true` — download the full dump first (needs ~10 GB free disk)
  - `resume_from:` — line number to resume from after a crash (see the
    progress logs; upserts are idempotent so overlapping is harmless)

  Returns `{:ok, %{imported: n}}` or `{:error, reason}`.
  """
  def run(opts \\ []) do
    with {:ok, path} <- resolve_dump(opts) do
      import_file(path, Keyword.take(opts, [:resume_from]))
    end
  end

  @doc """
  Streams one JSONL(.gz) file of OFF products into the database. Shared by
  `run/1` (the full dump) and the weekly delta worker (daily delta files).

  Returns `{:ok, %{imported: n}}`.
  """
  def import_file(path, opts \\ []) do
    resume_from = Keyword.get(opts, :resume_from, 0)
    known_languages = FoodProducts.known_language_codes()

    Logger.info("[BulkImporter] Starting import from #{path} (resume_from=#{resume_from})")
    started_at = System.monotonic_time(:second)

    imported =
      path
      |> open_stream()
      |> Stream.with_index(1)
      |> Stream.drop(resume_from)
      |> Stream.each(fn {_line, line_number} ->
        if rem(line_number, @progress_every) == 0 do
          elapsed = System.monotonic_time(:second) - started_at
          Logger.info("[BulkImporter] line #{line_number} (#{elapsed}s elapsed)")
        end
      end)
      |> Stream.map(fn {line, _n} -> ProductParser.parse_line(line, known_languages) end)
      |> Stream.filter(&match?({:ok, _, _}, &1))
      |> Stream.map(fn {:ok, attrs, translations} -> {attrs, translations} end)
      |> Stream.chunk_every(@chunk_size)
      |> Enum.reduce(0, fn chunk, imported ->
        imported + FoodProducts.upsert_products(chunk)
      end)

    elapsed = System.monotonic_time(:second) - started_at
    Logger.info("[BulkImporter] Done: #{imported} products imported in #{elapsed}s")
    {:ok, %{imported: imported}}
  end

  # ── private ──────────────────────────────────────────────────────────────────

  defp resolve_dump(opts) do
    cond do
      path = Keyword.get(opts, :path) ->
        if File.exists?(path), do: {:ok, path}, else: {:error, "no such file: #{path}"}

      Keyword.get(opts, :download, false) ->
        dest = Path.join(dump_dir(), "openfoodfacts-products.jsonl.gz")

        case off_client().download_dump(dest) do
          :ok -> {:ok, dest}
          {:error, reason} -> {:error, reason}
        end

      true ->
        {:error, "pass path: to an existing dump or download: true"}
    end
  end

  # `:compressed` makes File.stream! inflate gzip on the fly. If the dump ever
  # ships as multi-member gzip (where :compressed would stop at the first
  # member), pre-inflate it instead: `gunzip -k <dump>` and pass the .jsonl.
  defp open_stream(path) do
    if String.ends_with?(path, ".gz") do
      File.stream!(path, [:compressed], :line)
    else
      File.stream!(path, [], :line)
    end
  end

  defp dump_dir do
    Application.get_env(:mehungry, :off_dump_dir) || System.tmp_dir!()
  end

  defp off_client do
    Application.get_env(:mehungry, :off_client, Mehungry.OpenFoodFacts.Client)
  end
end
