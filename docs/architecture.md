# Architecture

Mehungry is a Phoenix **umbrella** application:

| App | Responsibility |
|---|---|
| `apps/mehungry` | Core domain: Ecto schemas, contexts, business logic, Oban workers, AI layer, external API clients |
| `apps/mehungry_web` | Web layer: LiveViews, controllers, components, plugs, OAuth strategies |

Deployed via Docker → GitHub Actions → AWS ECR → ECS; PostgreSQL 14 on RDS
(`eu-central-1`). Migrations run as a separate ECS task (`migrator/`).

## Dependency rule

`mehungry_web` depends on `mehungry` — never the reverse at compile time.

Two sanctioned **runtime** seams let core code reach web-owned infrastructure
without a compile-time dependency; both are `Application.get_env/3` module
lookups whose default is only resolved at call time:

1. `:social_media_publisher` (read by `RecipePublishWorker`) — defaults to
   `Mehungry.Social.Publisher`; `config/test.exs` points it at a stub.
   `Mehungry.SocialMediaPublisher` and `MehungryWeb.SocialMediaPublisher` survive only as defdelegate shims in
   case an environment still names them.
2. `:endpoint_module` (read by `Mehungry.Social.Pinterest`) — defaults to
   `MehungryWeb.Endpoint`; used to build public recipe links for pins.

## Context map (core app)

| Context | Notes |
|---|---|
| `Accounts` | Facade over `Accounts.{Auth, OAuth, Profiles, Rules, Admin, UserContent, Grading}` — see `docs/accounts.md` |
| `Food` | Facade over `Food.{Recipes, Ingredients, IngredientQueries, Nutrients, Measurements, Categories, Localization, Engagement}` — see `docs/food.md` |
| `Posts` | Community posts, comments, votes |
| `Inventory` | Shopping baskets |
| `Plans` | Meal plans |
| `Search` | Full-text recipe search (`Search.RecipeSearch`) |
| `Survey`, `Languages`, `Meta`, `History`, `Feedback` | Supporting contexts |
| `Professionals` | Nutritionist profiles, clients, appointments |
| `Subscriptions` | Tiers + Stripe quota enforcement |
| `AI.Bot` | Managed social-media recipe pipeline (`ai/bot/`) |
| `Billing` | Stripe checkout + webhooks (`Billing.StripeHandler`) |
| `Instagram` | Instagram Graph API context (`Instagram.Client` behind `Instagram.ClientBehaviour`, `:instagram_client` config key) |
| `Api.Facebook` / `Api.Pinterest` | Platform HTTP clients — see `docs/social_publishing.md` |
| `S3` | Single ExAws S3 wrapper (`apps/mehungry/lib/mehungry/s3.ex`); web keeps only `SimpleS3Upload` (LiveView presigned uploads) |

### Facade convention

`Mehungry.Food`, `Mehungry.Accounts`, and `Mehungry.Users` are permanent
`defdelegate` facades: every public function stays callable through them, so
call sites never break when internals move. New code may call sub-modules
directly. When adding a public function to a sub-module, add a matching
`defdelegate` to the facade.

## Caches (Cachex, started in `Mehungry.Application`)

| Cache | Limit | Key namespace | Writers/invalidators |
|---|---|---|---|
| `:recipes_cache` | 150 (LRU) | `{Mehungry.Food, id}` — pinned; `RecipePutNutrientsWorker` deletes under this key | `Food.Recipes` |
| `:cache_user_tokens` | — | `{Mehungry.Accounts, user_id}` — pinned | `Accounts.OAuth` |
| `:geo_cache` | 5000 (LRU) | — | `Meta` |

## Oban

Queues: `default: 10` (translations, publishing), `ai_agents: 2` (generation,
translation, images), `mailers: 5`.

Cron: `InstagramTokenRefreshWorker` 01:30, `DailyRecipeGenerationWorker`
02:00, `TelemetryPrunerWorker` 03:00 (UTC).

**Worker module names are load-bearing** — queued jobs in prod reference them
by name. Move logic out of workers freely, but never rename a worker module
without a migration plan for queued jobs.

## Supervision notes

- `MehungryWeb.SeedGenServerSuperServer` (`seeds_gen_server.ex`) runs in
  non-test environments and feeds `S3BrowserLive`'s bulk-import flow.
- Wallaby feature tests need `chromedriver` on `PATH` (the repo no longer
  vendors a binary — see `docs/operations.md`).

## Other docs

- `docs/food.md`, `docs/accounts.md` — split-context detail
- `docs/social_publishing.md` — publisher seam, per-platform clients
- `docs/web.md` — web-layer conventions and known debt
- `docs/operations.md` — deploy, env vars, secrets
- `docs/observability.md` — telemetry, error tracking, dashboards
- `docs/ai_agents.md` — AI layer
