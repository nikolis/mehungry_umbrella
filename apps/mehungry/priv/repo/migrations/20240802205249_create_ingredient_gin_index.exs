defmodule Mehungry.Repo.Migrations.CreateIngredientGinIndex do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;"

    execute """
      CREATE INDEX ingredient_name_gin_trgm_idx 
        ON ingredients 
        USING gin (name gin_trgm_ops);
    """
  end

  def down do
  end
end
