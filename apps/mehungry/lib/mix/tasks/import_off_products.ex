defmodule Mix.Tasks.Import.OffProducts do
  @shortdoc "Bulk-imports European food products (barcodes) from Open Food Facts"

  @moduledoc """
  Streams the Open Food Facts JSONL dump into the `food_products` table,
  filtered to European countries.

      mix import.off_products --path /data/openfoodfacts-products.jsonl.gz
      mix import.off_products --download
      mix import.off_products --path dump.jsonl.gz --resume-from 1240000
      mix import.off_products --path dump.jsonl.gz --match

  `--match` enqueues the ingredient-matching Oban worker after the import.
  In a prod release use `Mehungry.Release.import_off_products/1` instead.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [path: :string, download: :boolean, resume_from: :integer, match: :boolean]
      )

    importer_opts =
      opts
      |> Keyword.take([:path, :download, :resume_from])

    case Mehungry.OpenFoodFacts.BulkImporter.run(importer_opts) do
      {:ok, %{imported: imported}} ->
        Mix.shell().info("Imported #{imported} products from Open Food Facts.")

        if opts[:match] do
          %{} |> Mehungry.ObanWorkers.ProductIngredientMatchWorker.new() |> Oban.insert!()
          Mix.shell().info("Ingredient matching job enqueued. Check Oban for progress.")
        end

      {:error, reason} ->
        Mix.raise("OFF import failed: #{inspect(reason)}")
    end
  end
end
