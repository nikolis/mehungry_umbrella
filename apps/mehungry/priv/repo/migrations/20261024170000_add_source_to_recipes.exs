defmodule Mehungry.Repo.Migrations.AddSourceToRecipes do
  use Ecto.Migration

  # Provenance marker for recipes imported from an external data source
  # (e.g. "myplate"). nil = authored in-app (user/AI/bot). Lets imported batches
  # be identified and group-managed (filter, bulk delete) independently of
  # user-authored content.
  def change do
    alter table(:recipes) do
      add :source, :string
    end

    create index(:recipes, [:source])
  end
end
