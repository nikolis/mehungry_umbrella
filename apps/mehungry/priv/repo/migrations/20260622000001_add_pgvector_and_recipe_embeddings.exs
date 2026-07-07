defmodule Mehungry.Repo.Migrations.AddPgvectorAndRecipeEmbeddings do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    alter table(:recipes) do
      add :embedding, :vector, size: 1536
    end

    execute(
      "CREATE INDEX ON recipes USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS recipes_embedding_idx")

    alter table(:recipes) do
      remove :embedding
    end

    execute("DROP EXTENSION IF EXISTS vector")
  end
end
