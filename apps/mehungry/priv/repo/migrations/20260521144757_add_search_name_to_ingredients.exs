# priv/repo/migrations/XXXXXXXXXXXXXX_add_search_name_to_ingredients.ex

defmodule Mehungry.Repo.Migrations.AddSearchNameToIngredients do
  use Ecto.Migration

  def up do
    # Step 1: Add the search_name column
    alter table(:ingredients) do
      add :search_name, :string
    end

    # Step 2: Backfill existing data
    # This removes punctuation, converts to lowercase, and collapses spaces
    execute """
    UPDATE ingredients 
    SET search_name = regexp_replace(
      regexp_replace(
        regexp_replace(LOWER(name), '[^a-z0-9\\s]', ' ', 'g'),
        '\\s+', ' ', 'g'
      ),
      '^\\s+|\\s+$', '', 'g'
    )
    """

    # Step 3: Create indexes for fast prefix searching
    create index(:ingredients, [:search_name])

    # Also create a trigram index for fuzzy matching (optional but helpful)
    execute "CREATE INDEX IF NOT EXISTS ingredients_search_name_trgm_idx ON ingredients USING gin (search_name gin_trgm_ops);"
  end

  def down do
    drop index(:ingredients, [:search_name])
    execute "DROP INDEX IF EXISTS ingredients_search_name_trgm_idx;"

    alter table(:ingredients) do
      remove :search_name
    end
  end
end
