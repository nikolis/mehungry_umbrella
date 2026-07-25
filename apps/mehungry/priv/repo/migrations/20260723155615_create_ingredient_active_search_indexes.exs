defmodule Mehungry.Repo.Migrations.CreateIngredientActiveSearchIndexes do
  use Ecto.Migration

  # CREATE INDEX CONCURRENTLY does not block reads or writes, but it cannot run
  # inside a transaction and cannot hold the Ecto migration advisory lock — so
  # both must be disabled. This is the zero-downtime half of a two-step rollout:
  # here we ADD the Branded-excluding partial indexes alongside the existing full
  # ones; a later migration drops the full ones once query plans confirm these
  # are in use.
  @disable_ddl_transaction true
  @disable_migration_lock true

  # Predicate uses IS DISTINCT FROM (not <>) so rows with a NULL food_class are
  # KEPT in the index — only genuine "Branded" rows are excluded. User-facing
  # search queries carry the same predicate so the planner can use these.
  @predicate "food_class IS DISTINCT FROM 'Branded'"

  @indexes [
    # Partial mirror of ingredients_search_name_index (btree prefix search).
    {"ingredients_search_name_active_idx", "(search_name)"},
    # Partial mirror of ingredient_name_gin_trgm_idx (fuzzy word_similarity/%).
    {"ingredients_name_gin_trgm_active_idx", "USING gin (name gin_trgm_ops)"},
    # Partial mirror of ingredients_search_name_trgm_idx.
    {"ingredients_search_name_trgm_active_idx", "USING gin (search_name gin_trgm_ops)"},
    # Partial mirror of ingredient_searchable_idx (websearch_to_tsquery).
    {"ingredients_searchable_active_idx", "USING gin (searchable)"}
  ]

  def up do
    for {name, spec} <- @indexes do
      execute(
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name} ON ingredients #{spec} WHERE #{@predicate};"
      )
    end
  end

  def down do
    for {name, _spec} <- @indexes do
      execute("DROP INDEX CONCURRENTLY IF EXISTS #{name};")
    end
  end
end
