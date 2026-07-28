defmodule Mehungry.Repo.Migrations.DropIngredientFullSearchIndexes do
  use Ecto.Migration

  # ┌─────────────────────────────────────────────────────────────────────────┐
  # │ RELEASE B — DEPLOY LATER. This file lives in priv/repo/migrations_release_b│
  # │ (NOT the auto-run migrations/ dir) precisely so `mix ecto.migrate` does   │
  # │ not drop the old indexes in the same release that created the partials.   │
  # │                                                                           │
  # │ Promote it only after Release A is live in production AND `EXPLAIN` on the │
  # │ user-facing search queries confirms they use the *_active_idx partial     │
  # │ indexes — then move this file into priv/repo/migrations/ and deploy.      │
  # │ Afterwards admin search over the whole corpus (including a Branded-only   │
  # │ filter) falls back to a seq scan — an accepted trade-off for a low-traffic│
  # │ internal tool.                                                            │
  # └─────────────────────────────────────────────────────────────────────────┘
  #
  # DROP INDEX CONCURRENTLY does not block reads or writes but cannot run inside
  # a transaction or hold the migration advisory lock.
  @disable_ddl_transaction true
  @disable_migration_lock true

  # {full_index_name, recreate_spec} — recreate_spec used by down/0 to rebuild
  # the full (non-partial) index if we ever roll back.
  @indexes [
    {"ingredients_search_name_index", "(search_name)"},
    {"ingredient_name_gin_trgm_idx", "USING gin (name gin_trgm_ops)"},
    {"ingredients_search_name_trgm_idx", "USING gin (search_name gin_trgm_ops)"},
    {"ingredient_searchable_idx", "USING gin (searchable)"}
  ]

  def up do
    for {name, _spec} <- @indexes do
      execute("DROP INDEX CONCURRENTLY IF EXISTS #{name};")
    end
  end

  def down do
    for {name, spec} <- @indexes do
      execute("CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name} ON ingredients #{spec};")
    end
  end
end
