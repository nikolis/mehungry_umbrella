# Operations

## Deploy pipeline

**Fly.io** (`fly.toml`, app `m3hungry`, region `lhr`): `fly deploy` builds the
`Dockerfile` into a Phoenix release and does a **rolling** deploy across 2
`shared-cpu-1x`/1GB machines, gated on the `GET /health` liveness probe.
Migrations run in a one-off machine via `[deploy] release_command`
(`/app/bin/mehungry_umbrella eval MehungryWeb.Release.migrate`) **before** the
new release goes live. PostgreSQL is **Supabase** (session pooler, see `CLAUDE.md`
→ *Deployment Notes*).

> **History:** previously AWS ECS/ECR + RDS. The leftover `task-definition.json`
> / `migrator/` artifacts are from that era; `fly.toml` is the live config.

## Environment variables

See the canonical list in `CLAUDE.md` (Environment Variables section):
database, `SECRET_KEY_BASE`, `ANTHROPIC_API_KEY`, Stripe keys/price IDs, AWS
credentials + assets bucket, Facebook/Google/Instagram OAuth, optional
`FDC_API_KEY` / `OPENAI_API_KEY`, optional Turnstile keys.

## Secrets hygiene

- Never keep secrets in repo-root scratch files. `.gitignore` now blocks
  `secret_*.txt`, `*.log`, `output*.txt`.
- **2026-07-18**: a `secret_anthropic.txt` containing an Anthropic API key
  sat unignored in the repo root (never committed). The file was deleted;
  the key should be rotated.
- The legacy hardcoded FDC API key fallback was removed from the USDA clients
  (2026-07-19); `FDC_API_KEY` must be set and the leaked key rotated at USDA.

## Local testing

- `mix test` from the umbrella root. Wallaby feature tests
  (`apps/mehungry_web/test/features/`, `test/mehungry_web/features/`) need
  `chromedriver` on `PATH` — the repo no longer vendors
  `chromedriver-linux64/`. Install a chromedriver matching your Chrome and
  ensure it is on `PATH`; without it the feature tests fail with
  "invalid session id" (a known pre-existing local condition).
- Wallaby config: `config/test.exs`.

## Admin maintenance tooling

- `/professional/maintenance` (admin-gated) triggers the one-off backfills in
  `apps/mehungry/lib/mehungry/maintenance_utils/` (mass/volume unit
  backfills). They are kept because the admin UI reaches them; retire them
  via a product decision, not a dead-code sweep.
- `/professional/files` (`S3BrowserLive`) browses the assets bucket via
  `Mehungry.S3` and can enqueue bulk imports through
  `SeedsGenWorkerServer`.
- Mix tasks: `dedupe_aliases`, `import_off_products`, `knowledge.schemas`,
  `translate_ingredients`.
