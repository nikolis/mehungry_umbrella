defmodule Mix.Tasks.Taxonomy.Classify do
  @shortdoc "Enqueues Oban jobs to AI-classify ingredients into the bio-nutritional taxonomy"

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    case Mehungry.Food.Taxonomies.get_taxonomy_by_slug("bio-nutritional") do
      nil ->
        Mix.raise("Taxonomy 'bio-nutritional' not found. Run `mix taxonomy.seed` first.")

      taxonomy ->
        {:ok, _job} = Mehungry.ObanWorkers.TaxonomyClassificationWorker.enqueue(taxonomy.id)
        Mix.shell().info("Taxonomy classification job enqueued. Check Oban for progress.")
    end
  end
end
