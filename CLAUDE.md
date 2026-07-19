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
| `Accounts` | Facade over `Accounts.{Auth, OAuth, Profiles, Rules, Admin, UserContent, Grading}` — see `docs/accounts.md`. `Mehungry.Users` is a deprecated facade over the same sub-modules |
| `Food` | Facade over `Food.{Recipes, Ingredients, IngredientQueries, Nutrients, Measurements, Categories, Localization, Engagement}` — see `docs/food.md` |
| `Inventory` | Shopping baskets and basket items |
| `Plans` | Meal plans and daily meal plans |
| `Posts` | Posts, comments, comment answers, votes |
| `Search` | Full-text recipe search |
| `Survey` | User dietary preference surveys |
| `Languages` | Multi-language translations for ingredients and units |
| `Meta` | Visit tracking |
| `History` | User activity history |
| `Professionals` | Nutritionist profiles, client invitations, assignments, appointments, meal plan ratings |
| `Subscriptions` | Subscription tiers, Stripe integration, AI feature quota enforcement |
| `AI.Bot` | Managed social media recipe pipeline — monthly configs, review queue, translations, post logs |
| `Billing` | Stripe checkout sessions and webhook handling (`Billing.StripeHandler`) |
| `Social` | Social platform layer (`social/`): `Social.Publisher` fan-out (behind `Social.PublisherBehaviour`), `Social.{Facebook, Pinterest}` HTTP clients, and the `Social.Instagram` context — see `docs/social_publishing.md` |
| `FoodData` | External food-data sources (`food_data/`): `FoodData.Usda.{SearchClient, FdcClient, FoodParser, SeedFileParser}`, `FoodData.OpenFoodFacts.*`, `FoodData.SpoonacularImporter` |
| `S3` | The single ExAws S3 wrapper (`s3.ex`) — use it instead of inline `ExAws.S3` calls |

**Facade convention:** `Mehungry.Food`, `Mehungry.Accounts`, and
`Mehungry.Users` are permanent defdelegate facades — public functions never
break when internals move. New code may call sub-modules directly; when adding
a public function to a sub-module, add a matching `defdelegate` to the facade.
Architecture overview: **`docs/architecture.md`**.

**Cachex** runs three named caches started in `Mehungry.Application`:
- `:recipes_cache` — LRU, limit 150
- `:cache_user_tokens`
- `:geo_cache` — LRU, limit 5000

### AI Subsystem (`apps/mehungry/lib/mehungry/ai/`)

A custom Anthropic API layer — do not use raw HTTPoison calls for AI work:

- `AI.Client` — shared HTTP client for the Anthropic Messages API. Handles auth, retries (exponential backoff on 529 rate-limit and timeouts), and response parsing. Default model: `claude-haiku-4-5-20251001`, default max_tokens: 2048.
- `AI.Agent` — generic tool-use loop. Runs a conversation until `end_turn` or `max_iterations` (default 10). Accepts a `handler` function `fn(tool_name, input, context) -> result` and dispatches tool calls automatically.
- `AI.Agents.RecipeAgent`, `MealPlanAgent`, `NutritionistAgent` — domain-specific agents built on `AI.Agent`.
- `AI.ImageGenerator`, `AI.IngredientTranslator`, `AI.RecipeTranslator`, `AI.MealPlanGenerator` — standalone AI utilities.

Config key: `:anthropic_api_key` (read from `ANTHROPIC_API_KEY` env var in `runtime.exs`).

### AI Bot Pipeline (`apps/mehungry/lib/mehungry/ai/bot/`)

Automated recipe-to-social-media pipeline:

1. `AiBotConfig` — monthly config with theme, bot user, and `publish_times` map (meal_type → language → UTC time string).
2. `WeekConfig` / `DayConfig` — optional sub-configs to override week/day themes.
3. `AiBotRecipe` — tracks each generated recipe with status: `pending_review → approved/rejected → published`.
4. Oban cron fires `DailyRecipeGenerationWorker` at **2am UTC daily** → generates one recipe per meal type via `RecipeAgent` → schedules `RecipePublishWorker` jobs (one per meal × language) at the times in `publish_times`.
5. Admin reviews at `/professional/ai-bot/review` before publish jobs run.
6. `RecipePublishWorker` calls `Mehungry.Social.Publisher.publish_recipe/5` (mockable via app config key `:social_media_publisher`) — see `docs/social_publishing.md`.
7. `AI.Bot.Notifier` sends admin email when batch is ready for review.

### Subscription Tiers (`Mehungry.Subscriptions`)

Three tiers enforced via `check_quota/2` and `record_usage/2`:
- `"free"` — 0 recipe generations / 0 meal plans per month
- `"m3hungry_plus"` — 15 / 4 per month (consumer premium, billed via Stripe)
- `"pro"` — 30 / 10 per month (nutritionist tier, billed via Stripe)

The owner email (`nikolisgal@gmail.com`) bypasses all quota checks. Use `Subscriptions.pro?/1` and `Subscriptions.nutritionist?/1` for gate checks.

Stripe events are handled via `POST /webhooks/stripe` → `StripeWebhookController` → `Billing.StripeHandler`.

### Oban Queues

```
default:    10 concurrent  — ingredient translation, recipe publishing
ai_agents:   2 concurrent  — recipe generation, translation, image generation, nutritionist agent
mailers:     5 concurrent  — email
```

Cron: `InstagramTokenRefreshWorker` at `30 1 * * *`, `DailyRecipeGenerationWorker` at `0 2 * * *`, `TelemetryPrunerWorker` at `0 3 * * *`.

### Instagram Integration (`Mehungry.Social.Instagram`)

Core-app context for the Instagram Graph API: `Social.Instagram.Token` (token map lifecycle/status), `Social.Instagram.Caption` (2200-char capped captions), `Social.Instagram.Client` behind `Social.Instagram.ClientBehaviour` (stubbed in tests via `:instagram_client` config key). Long-lived tokens are refreshed daily by `InstagramTokenRefreshWorker`; invalid tokens are marked stale and surface as "reconnect" in `/professional/ai-bot/social`. `RecipePublishWorker` publish failures return `{:error, _}` for Oban retries, skipping platforms that already have an `"ok"` post log (manual re-publish passes `force: true`). The publisher seam is typed by `Mehungry.Social.PublisherBehaviour` (`:social_media_publisher` config key).

### Observability

Full operator's manual: **`docs/observability.md`** (architecture, metric reference, diagnostic playbooks, limitations). Summary: telemetry events fan out to live LiveDashboard metrics (`MehungryWeb.Telemetry`), a persistent snapshot store (`Mehungry.Telemetry.MetricsBuffer` → `telemetry_snapshots`, 5-min aggregates, 30-day retention), a DIY error tracker (`Mehungry.Telemetry.ErrorTracker` → `error_events`, fingerprint-deduped), and warning logs (`[SlowQuery]` ≥500ms, `[SlowRequest]` ≥2s, `[ProcessWatchdog]` mailbox ≥1000). Everything is viewed at `/dashboard` (admin-gated via `config :mehungry, :admin_email` + `MehungryWeb.Plugs.RequireAdmin`), including custom pages Metrics History and Errors. Error tracking is deliberately in-app (no Sentry) and dashboard-only (no alerting).

### Web Layer (`apps/mehungry_web/lib/mehungry_web/`)

All authenticated UI is built with **Phoenix LiveView**. Live sessions in `router.ex`:

| Session | `on_mount` | Routes |
|---|---|---|
| `:default` | `UserAuthLive` | `/basket`, `/calendar`, `/create_recipe`, `/upgrade`, `/posts`, etc. |
| `:default2` | `AdminAuthLive` | `/professional/**` (admin/internal tools) |
| `:nutritionist` | `NutritionistAuthLive` | `/nutritionist/**` (dashboard, clients, appointments) |
| `:maybe` | `MaybeUserAuthLive` | `/home`, `/browse`, `/search`, `/profile`, `/foods` |
| `:default3` | none | `/welcome` (landing) |

**Authentication** uses Ueberauth with Facebook, Google, and Instagram OAuth. Session state is injected via `on_mount` callbacks. `BotOAuthController` handles OAuth for bot social accounts (`/auth/bot/target/:bot_user_id/:provider`).

**Presence** (`MehungryWeb.Presence`) tracks active users and records visits. Live views opt in with `use MehungryWeb.Presence, :user_tracking`.

### Frontend

- **Tailwind CSS** + **DaisyUI** for styling
- **Alpine.js** for client-side interactivity
- **jQuery** + **Select2/Selectize** — legacy select components (being phased out)
- **Vega-Lite** for charts via `Hooks.VegaLite` and `Hooks.ResponsiveChart` JS hooks
- **esbuild** bundles JS; `mix assets.build` / `mix assets.deploy` compile assets

Client hooks: `apps/mehungry_web/assets/js/hooks.js`. Navigation active-state handled by a JS `Proxy` intercepting URL changes (`navigation.js`).

### Modal Approaches

Three coexisting patterns — prefer option 3 for new code:
1. CSS + `Phoenix.LiveView.JS` — recipe browser
2. CSS + client Hooks — elsewhere
3. `core_components.ex` modal — **preferred for new code**

## Testing Layers

1. **Unit** — `ExUnit` in `apps/mehungry/test/`
2. **Integration/smoke** — `ExUnit` with `ConnCase`/`LiveViewTest` in `apps/mehungry_web/test/`
3. **Functional** — Wallaby (browser-driven) in `apps/mehungry_web/test/features/`

Wallaby tests require a `chromedriver` binary on `PATH` (no longer vendored in the repo — see `docs/operations.md`).

## LiveView Conventions

- Build Live Components with a clear division between **View (Render)** and **Update** code.
- Define view functions in the order they are invoked, starting with `render`.

**Hierarchical Selection pattern** — when picking the first non-nil value from a priority-ordered set of sources:

```elixir
case {first, second, third} do
  {nil, nil, nil} -> default
  {nil, nil, third} -> third
  {nil, second, _} -> second
  {first, _, _} -> first
end
```

## Environment Variables

Required at runtime:
- `DATABASE_URL` — PostgreSQL connection string (watch for stray spaces when copy-pasting)
- `SECRET_KEY_BASE`
- `ANTHROPIC_API_KEY` — for all AI features
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRO_PRICE_ID`, `STRIPE_PRO_YEARLY_PRICE_ID` (consumer `m3hungry_plus` tier), `STRIPE_NUTRITIONIST_PRICE_ID`, `STRIPE_NUTRITIONIST_YEARLY_PRICE_ID` (nutritionist `pro` tier)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ASSETS_BUCKET_NAME`
- `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `INSTAGRAM_CLIENT_ID`, `INSTAGRAM_CLIENT_SECRET`
- `PINTEREST_CLIENT_ID`, `PINTEREST_CLIENT_SECRET`; `PINTEREST_ENV` selects the API environment — `live` for the real API, anything else (or unset) for the sandbox
- `FDC_API_KEY` — required for USDA food lookups (basket search + AI ingredient creation); there is no fallback key
- `OPENAI_API_KEY` — optional (embeddings, cover images)
- `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` — Cloudflare Turnstile CAPTCHA on registration (optional; verification is skipped when the secret key is unset)

## Deployment Notes

- PostgreSQL version 14 is required; newer versions may not work with the current ECS setup.
- The migrator app (`migrator/`) runs DB migrations as a separate ECS task.
- Task definitions are in `task-definition.json` and `migrator-task-definition.json`.
- AWS region: `eu-central-1`.
