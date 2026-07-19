# Scripts

Helper scripts that regenerate the codebase knowledge base in `docs/knowledge/`.
Run them from the umbrella root.

## update_knowledge.sh

The orchestrator — regenerates the whole `docs/knowledge/` directory:

1. `tree apps/mehungry/lib apps/mehungry_web/lib` → `project_tree.md`
2. `mix phx.routes` → `routes.md`
3. `mix deps.tree` → `dependencies.md`
4. `./scripts/generate_contexts.sh` → `contexts.md`
5. `mix knowledge.schemas` → `schemas.md` + `domain_graph.md`
   (Mix task at `apps/mehungry/lib/mix/tasks/knowledge.schemas.ex`)
6. `./scripts/generate_features.sh` → `features.md`

```bash
./scripts/update_knowledge.sh
```

## generate_contexts.sh

Writes `docs/knowledge/contexts.md`: for every `.ex` file under
`apps/mehungry/lib/mehungry`, emits the first `defmodule` line as a heading
followed by the file's top-level `def` lines (matched by two-space indent),
giving a quick public-API overview of each context module.

## generate_features.sh

Writes `docs/knowledge/features.md`: one section per directory under
`apps/mehungry/lib/mehungry/`, listing the `.ex` files it contains — a
feature-by-feature file inventory of the core app.

## Notes

- Schema/domain-graph generation lives in the `mix knowledge.schemas` task,
  not a shell script (a former `generate_schemas.sh` was superseded by it and
  removed).
- The generated files are plain snapshots; rerun `update_knowledge.sh` after
  structural changes (new modules, routes, schemas, deps).

## TODO

- `mix phx.routes` fails (exit 1) when run from the umbrella root because it
  can't infer the router, so `routes.md` ends up empty. Fix: call
  `mix phx.routes MehungryWeb.Router` in `update_knowledge.sh` (verified to
  work), or add a `"phx.routes"` alias in the root `mix.exs`.
- `update_knowledge.sh` has no `set -e`, so a failing step (like the routes
  one above) is silently ignored and leaves stale or empty output files.
- `generate_contexts.sh` only matches lines starting with `  def `, so it
  misses `defdelegate` — the entire public API of the `Mehungry.Food`,
  `Mehungry.Accounts`, and `Mehungry.Users` facades is absent from
  `contexts.md`.
- `generate_contexts.sh` writes into `docs/knowledge/` without creating it
  first; it fails if run standalone before `update_knowledge.sh` has made the
  directory.
- `update_knowledge.sh` requires the external `tree` binary (present on this
  machine, but not checked for).
