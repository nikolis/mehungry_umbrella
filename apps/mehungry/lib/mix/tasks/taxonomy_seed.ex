defmodule Mix.Tasks.Taxonomy.Seed do
  @shortdoc "Seeds the Biological/Nutritional ingredient taxonomy node tree"

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    taxonomy = Mehungry.Food.TaxonomySeeder.seed()
    node_count = length(Mehungry.Food.Taxonomies.list_nodes(taxonomy.id))
    Mix.shell().info("Taxonomy '#{taxonomy.slug}' seeded with #{node_count} nodes.")
  end
end
