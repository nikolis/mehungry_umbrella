# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mehungry is a food/recipe social platform built as a **Phoenix Umbrella** application with two apps:
- `apps/mehungry` — core domain layer (Ecto schemas, contexts, business logic)
- `apps/mehungry_web` — Phoenix web layer (LiveViews, controllers, components)

Deployed via Docker → GitHub Actions → AWS ECR → AWS ECS, with PostgreSQL on AWS RDS (v14).

## Development Commands

```bash
# Initial setup (deps + DB create + migrate + seed)
mix setup

# Start server
mix phx.server
iex -S mix phx.server

# Database
mix ecto.migrate
mix ecto.reset          # drop + recreate + migrate + seed

# Build assets (dev)
mix assets.build

# Run all tests
mix test

# Run a single test file
mix test apps/mehungry/test/mehungry/food_test.exs

# Run a single test by line number
mix test apps/mehungry/test/mehungry/food_test.exs:42

# Static analysis
mix credo
mix dialyzer
```

## Architecture

### Domain Contexts (`apps/mehungry/lib/mehungry/`)

| Context | Responsibility |
|---|---|
| `Accounts` | Users, auth tokens, follows, profile, ingredient/category rules |
| `Food` | Recipes, ingredients, nutrients, measurement units, categories, hashtags |
| `Inventory` | Shopping baskets and basket items |
| `Plans` | Meal plans and daily meal plans |
| `Posts` | Posts, comments, comment answers, votes |
| `Search` | Full-text recipe search |
| `Survey` | User dietary preference surveys |
| `Languages` | Multi-language translations for ingredients and units |
| `Meta` | Visit tracking |
| `History` | User activity history |

Cachex runs two named caches: `:recipes_cache` (LRU, limit 150) and `:cache_user_tokens`. Both are started in `Mehungry.Application`.

### Web Layer (`apps/mehungry_web/lib/mehungry_web/`)

All authenticated UI is built with **Phoenix LiveView**. Key live sessions in `router.ex`:
- `:default` — authenticated routes (`/profile`, `/basket`, `/calendar`, `/create_recipe`, etc.)
- `:default2` — professional/admin routes under `/professional/`
- `:maybe` — public-facing routes (`/home`, `/browse`, `/search`)

**Authentication** uses Ueberauth with Facebook, Google, and Instagram OAuth providers. Session state is injected in LiveView `on_mount` callbacks (`UserAuthLive`, `AdminAuthLive`, `MaybeUserAuthLive`).

**Presence** (`MehungryWeb.Presence`) tracks active users and records visits. Live views use `use MehungryWeb.Presence, :user_tracking` to opt in.

### Frontend

- **Tailwind CSS** + **DaisyUI** for styling
- **Alpine.js** for client-side interactivity
- **jQuery** + **Select2/Selectize** for legacy select components (being phased out)
- **Vega-Lite** for charts (via `Hooks.VegaLite` and `Hooks.ResponsiveChart` JS hooks)
- **esbuild** bundles JS; `mix assets.build` / `mix assets.deploy` compile assets

Client hooks are defined in `apps/mehungry_web/assets/js/hooks.js`. Navigation active-state highlighting is handled in JS via a `Proxy` intercepting URL changes (see `navigation.js`).

### Modal Approaches

Two coexisting patterns (documented in `apps/mehungry_web/README.md`):
1. CSS + `Phoenix.LiveView.JS` — used in recipe browser
2. CSS + client Hooks — used elsewhere
3. `core_components.ex` modal (preferred for new code)

## Testing Layers

Tests follow a layered strategy (run the faster layers first):
1. **Unit** — `ExUnit` in `apps/mehungry/test/`
2. **Integration/smoke** — `ExUnit` with `ConnCase`/`LiveViewTest` in `apps/mehungry_web/test/`
3. **Functional** — Wallaby (browser-driven) in `apps/mehungry_web/test/features/`

Wallaby tests require ChromeDriver. The `chromedriver-linux64` binary is in the repo root.

## LiveView Conventions

From `README.md`:
- Build Live Components with a clear division between **View (Render)** and **Update** code.
- Define view functions in the order they are invoked, starting with `render`.

**Hierarchical Selection pattern** — when picking the first non-nil value from a priority-ordered set of sources, use a tuple case match:

```elixir
case {first, second, third} do
  {nil, nil, nil} -> default
  {nil, nil, third} -> third
  {nil, second, _} -> second
  {first, _, _} -> first
end
```

## Environment Variables

Required at runtime (set as Docker build args and ECS task environment):
- `DATABASE_URL` — PostgreSQL connection string (watch for stray spaces when copy-pasting)
- `SECRET_KEY_BASE`
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ASSETS_BUCKET_NAME`
- `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `INSTAGRAM_CLIENT_ID`, `INSTAGRAM_CLIENT_SECRET`

## Deployment Notes

- PostgreSQL version 14 is required; newer versions may not work with the current ECS setup.
- The migrator app (`migrator/`) runs DB migrations as a separate ECS task.
- Task definitions are in `task-definition.json` and `migrator-task-definition.json`.
- AWS region: `eu-central-1`.
