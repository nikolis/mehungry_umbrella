defmodule Mix.Tasks.Taxonomy.Seed do
  @shortdoc "Idempotently seeds the bio-nutritional ingredient taxonomy"

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_args) do
    taxonomy = Mehungry.Food.TaxonomySeeder.seed()
    node_count = taxonomy.id |> Mehungry.Food.list_nodes() |> length()
    Mix.shell().info("Seeded taxonomy #{taxonomy.slug} with #{node_count} nodes.")
  end
end
