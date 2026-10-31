# Architecture

Mehungry is a Phoenix **umbrella** application:

| App | Responsibility |
|---|---|
| `apps/mehungry` | Core domain: Ecto schemas, contexts, business logic, Oban workers, AI layer, external API clients |
| `apps/mehungry_web` | Web layer: LiveViews, controllers, components, plugs, OAuth strategies |

Deployed on **Fly.io** (Docker image → Phoenix release; app `m3hungry`, region
`lhr`, 2 `shared-cpu-1x` machines, rolling deploys gated on `GET /health`).
PostgreSQL is **Supabase** (session pooler, `POOL_SIZE=10`/machine). Migrations
run as a one-off machine via the `[deploy] release_command` in `fly.toml`
(`MehungryWeb.Release.migrate`). See `CLAUDE.md` → *Deployment Notes* for the
full topology.

> **History:** the app previously ran on AWS ECS/ECR + RDS (`eu-central-1`); the
> `task-definition.json` / `migrator/` artifacts are leftovers from that era.
> `fly.toml` is the live config.

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
| `Accounts` | Facade over `Accounts.{Auth, OAuth, Profiles, Rules, Admin, UserContent, Grading}` — see `docs/users/accounts.md` |
| `Food` | Facade over `Food.{Recipes, Ingredients, IngredientQueries, Nutrients, Measurements, Categories, Localization, Engagement}` — see `docs/food/food.md` |
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

Queues (total concurrency capped at **13** to fit the Supabase pool — see
`CLAUDE.md` → *Oban Queues*): `default: 5`, `ai_agents: 1`, `mailers: 3`,
`imports: 1` (condition-seeded crawl + research ingestion), `seed_imports: 1`
(USDA S3 seed files), `hashtag_reconcile: 1`, `portion_generation: 1`.

Cron (UTC): `InstagramTokenRefreshWorker` 01:30, `PinterestTokenRefreshWorker`
01:45, `DailyRecipeGenerationWorker` 02:00, `PipelineWatchdogWorker` every 10
min. (The old `TelemetryPrunerWorker` cron was **removed** with the DIY
observability layer — see [`observability.md`](observability.md).)

**Worker module names are load-bearing** — queued jobs in prod reference them
by name. Move logic out of workers freely, but never rename a worker module
without a migration plan for queued jobs.

## Supervision notes

- `MehungryWeb.SeedGenServerSuperServer` (`seeds_gen_server.ex`) runs in
  non-test environments and feeds `S3BrowserLive`'s bulk-import flow.
- Wallaby feature tests need `chromedriver` on `PATH` (the repo no longer
  vendors a binary — see `docs/operations.md`).

## Other docs

- `docs/food/food.md`, `docs/users/accounts.md` — split-context detail
- `docs/social_publishing.md` — publisher seam, per-platform clients
- `docs/web.md` — web-layer conventions and known debt
- `docs/operations.md` — deploy, env vars, secrets
- `docs/observability.md` — telemetry, error tracking, dashboards
- `docs/ai/ai_agents.md` — AI layer
