# Release B migrations (deploy later)

Migrations in this folder are **intentionally excluded** from the auto-run
`priv/repo/migrations/` path so `mix ecto.migrate` does not execute them yet.

## `20260723151603_drop_ingredient_full_search_indexes.exs`

Drops the four old full ingredient search indexes, leaving only the
Branded-excluding `*_active_idx` partials created in Release A
(`CreateIngredientActiveSearchIndexes`).

**Promote when ready:**

1. Confirm Release A is live and `EXPLAIN` on the user-facing ingredient search
   queries uses the `*_active_idx` partial indexes (see the plan's verification
   section).
2. `git mv` this file into `priv/repo/migrations/`.
3. Deploy — the migrator ECS task runs it via `mix ecto.migrate`.
