defmodule Mehungry.Repo.Migrations.IngredientSearchMigration do
  use Ecto.Migration

  def up do
    execute """
      ALTER TABLE ingredients
        ADD COLUMN searchable tsvector
        GENERATED ALWAYS AS (
          setweight(to_tsvector('english', coalesce(name, '')), 'A') ||
          setweight(to_tsvector('english', coalesce(description, '')), 'B')
        ) STORED;
    """

    execute """
    CREATE INDEX ingredient_searchable_idx ON ingredients USING gin(searchable);
    """
  end

  def down do
    execute """
      DROP INDEX ingredient_searchable_idx ; 
      ALTER TABLE ingredients 
      DROP COLUMN searchable;
    """
  end
end
