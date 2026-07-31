defmodule Mehungry.Repo.Migrations.AddCanonicalFoodEmbeddings do
  use Ecto.Migration

  # Semantic embedding of each canonical-food name, so the parser's
  # SemanticSuggester can nearest-neighbour an unresolved surface string against
  # the lexicon. 384-dim = all-MiniLM-L6-v2. The `vector` extension is already
  # installed by the recipe-embeddings migration; guarded here for standalone runs.
  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    alter table(:canonical_foods) do
      add :embedding, :vector, size: 384
      add :embedding_model, :string
    end

    execute(
      "CREATE INDEX canonical_foods_embedding_idx ON canonical_foods USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)"
    )
  end

  def down do
    execute("DROP INDEX IF EXISTS canonical_foods_embedding_idx")

    alter table(:canonical_foods) do
      remove :embedding
      remove :embedding_model
    end
  end
end
