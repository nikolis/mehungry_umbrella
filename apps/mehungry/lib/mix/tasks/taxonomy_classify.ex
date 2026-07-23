defmodule Mix.Tasks.Taxonomy.Classify do
  @shortdoc "Enqueues Oban jobs to classify all ingredients into the bio-nutritional taxonomy"

  use Mix.Task

  @requirements ["app.start"]

  @slug "bio-nutritional"

  @impl Mix.Task
  def run(_args) do
    case Mehungry.Food.get_taxonomy_by_slug(@slug) do
      nil ->
        Mix.shell().error("Taxonomy #{@slug} not found. Run `mix taxonomy.seed` first.")

      taxonomy ->
        %{"taxonomy_id" => taxonomy.id}
        |> Mehungry.ObanWorkers.TaxonomyClassificationWorker.new()
        |> Oban.insert!()

        Mix.shell().info("Taxonomy classification job enqueued. Check Oban for progress.")
    end
  end
end
