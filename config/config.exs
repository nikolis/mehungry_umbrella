# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of Mix.Config.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrellause Mix.Config
import Config
# Configure Mix tasks and generators
config :mehungry,
  ecto_repos: [Mehungry.Repo]

config :mehungry, :admin_email, "nikolisgal@gmail.com"

# Android closed-testing (Google Play) opt-in invite, sent from the admin panel
# at /professional/android-beta. Override in runtime.exs from env in prod.
#   * opt_in_url — the Google Play "become a tester" opt-in link for the track
#   * group_email — default recipient (a Google Group that fans out to testers)
config :mehungry, :android_beta,
  opt_in_url: "https://play.google.com/apps/testing/com.mehungry.app",
  group_email: "mehungry-android-testers@googlegroups.com",
  current_version: "1.0.0"

# Feed ranking: AI recipes are authored by these bot accounts. Their posts are
# penalized in Mehungry.Posts.list_posts/1 so human-created content out-ranks
# freshly generated AI content. Tune :ai_content_penalty to taste.
config :mehungry, :ai_bot_emails, ["nikolaos.galerakis@gmail.com", "nikolisgal@gmail.com"]
config :mehungry, :ai_content_penalty, 3.0

# ── Consultation payments (Stripe Connect) ──────────────────────────────────
# GO-LIVE GATE: while false, booking is request-only and service prices are
# display-only (money wired directly, outside M3Hungry). Do NOT flip to true in
# prod until the compliance prerequisites are done — see
# docs/implementation/professionals/payments/nutritionist_payments_build_plan.md §4.
config :mehungry, :consultation_payments_enabled, false
# Our flat platform commission (basis points): 500 = 5%.
config :mehungry, :platform_fee_bps, 500
# VAT contained within the (VAT-inclusive) commission: 2400 = 24% (Greek domestic).
config :mehungry, :platform_fee_vat_bps, 2400
# Client refund tiers: full refund if cancelling >= 24h out, 50% if >= 4h, else 0.
config :mehungry, :consultation_free_cancel_hours, 24
config :mehungry, :consultation_partial_refund_hours, 4
# Connected-account classification. We describe the service as non-medical
# nutrition/wellness coaching so Stripe's risk review lands in the right,
# unrestricted category. On Accounts v2 these are NOT sent at account creation
# (the v2 business-profile field shape differs); the nutritionist instead picks
# the "Health and wellness coaching" industry during Express onboarding, which is
# what Stripe auto-maps. Kept here as the canonical copy + for reference.
config :mehungry,
       :connect_product_description,
       "Nutrition and wellness coaching consultations booked through M3Hungry. Counseling and education — not medical diagnosis or treatment."

config :mehungry, :connect_business_url, "https://www.m3hungry.com"
# Which Stripe Accounts API the connected-account LIFECYCLE uses: :v1 (stable,
# live-verified — launch on this) or :v2 (Accounts v2, on a preview API version).
# Charging/refunds always stay on stable v1 regardless. Flip to :v2 once Accounts
# v2 is GA; requires "Accounts v1 support" enabled in the Stripe dashboard while :v1.
config :mehungry, :stripe_accounts_api, :v1
# Accounts v2 API version. Connect account lifecycle (create / onboarding link /
# status / account webhooks) runs on the v2 core endpoints, which are still
# delivered on a preview API version pinned here. Bump this when migrating to a
# newer preview, or once v2 leaves preview, to the GA version string. Only the
# /v2/core/* calls send it; subscriptions stay on the stable v1 endpoints.
config :mehungry, :stripe_accounts_api_version, "2026-10-28.preview"
# Home country stamped on each connected account at creation (ISO-3166 alpha-2).
# ~all nutritionists are in Greece; a non-GR nutritionist needs this overridden
# before they onboard (v2 account creation requires identity.country).
config :mehungry, :connect_account_country, "GR"
# Leave :connect_account_mcc UNSET — Stripe has no numeric "wellness coaching" MCC,
# and a manually set code must match the account's chosen industry or Stripe
# rejects/overrides it. Rely on industry auto-assignment. Only set this (to a
# 4-digit code Stripe confirms) if you ever need to force one.
# config :mehungry, :connect_account_mcc, "7298"

# Global social-publishing kill switches (see Mehungry.Social). Instagram and
# Pinterest are disabled for now due to problems with the platform apps
# themselves — no posts are attempted and their share entry points are hidden.
# Flip a flag to `true` to re-enable. Can be overridden at runtime via
# SOCIAL_PLATFORMS_DISABLED (see runtime.exs).
config :mehungry, :social_platforms,
  facebook: true,
  instagram: false,
  pinterest: true

# Compile-time env marker for the /test-accounts routes. In dev/test the routes
# are open; other envs additionally require a matching TEST_ACCOUNTS_TOKEN
# (set in runtime.exs). See MehungryWeb.TestAccountsController.
config :mehungry_web, :test_accounts_env, config_env()

# Base URL + shared-secret bearer token the non-deployed mehungry_local_ai service
# uses to reach the local-AI REST API. Overridden in runtime.exs from env vars.
config :mehungry_local_ai, server_base_url: "http://localhost:4000"

# Base URL of the mehungry_extractor batch-PMID analysis service (POST /analyze).
# Overridden in runtime.exs from the EXTRACTOR_BASE_URL env var.
config :mehungry, :extractor_base_url, "http://127.0.0.1:8000"

# Reference FDC dataset JSON files the /professional/usda-schema view derives
# its schema catalog from (Mehungry.FoodData.Usda.SchemaMatcher). A path or list
# of paths; when none is readable the catalog falls back to the ingredient
# corpus. Left empty here — set per-environment to the local seed files.
config :mehungry, :usda_schema_reference_paths, []

# Nx only loads inside the non-deployed apps/mehungry_local_ai service. Keep the
# global backend on the pure-Elixir binary backend; the QA serving there compiles
# with `compiler: EXLA` per-serving, so this doesn't force EXLA globally.
config :nx, default_backend: Nx.BinaryBackend

# The `image` library (a transitive dep) autostarts an ML image classifier /
# generator that default to the EXLA Nx compiler. We don't use those, and with
# EXLA disabled their supervised servers fail to boot — turn autostart off.
config :image, :classifier, autostart: false
config :image, :generator, autostart: false

# Timezone used for analytics "today" boundaries and daily buckets, so the
# dashboard lines up with the Google Analytics property timezone. Must be a
# valid Postgres/IANA zone name (e.g. "Europe/Athens", "Etc/UTC").
config :mehungry, :reporting_timezone, "Europe/Athens"

config :mehungry, Mehungry.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

# USDA FoodData Central rate-management tunables. Consumed by the shared
# `FoodData.Usda.FdcHttp` client and `ObanWorkers.IngredientReconciliationWorker`
# to pace lookups and snooze the reconciliation job when the FDC quota runs low
# or a 429 is returned. See docs/food/food.md / the worker moduledoc.
config :mehungry,
  # Delay (ms) between successive USDA lookups within a reconciliation batch.
  fdc_pace_ms: 250,
  # Snooze the batch early once the API's remaining quota drops to this.
  fdc_rate_floor: 5,
  # How long (s) to snooze when stopping early on low quota.
  fdc_low_remaining_snooze_seconds: 120,
  # Upper bound (s) applied to a 429 Retry-After before snoozing.
  fdc_max_snooze_seconds: 3600,
  # Delay (ms) between successive ingredient crawls in a literature-crawl batch.
  entrez_pace_ms: 300,
  # Upper bound (s) applied to an Entrez rate-limit Retry-After before snoozing.
  entrez_max_snooze_seconds: 3600,
  # Delay (ms) between successive study annotations in a PubTator3 batch.
  pubtator_pace_ms: 300,
  # Upper bound (s) applied to a PubTator rate-limit Retry-After before snoozing.
  pubtator_max_snooze_seconds: 3600,
  # Evidence-score cutoff (0.0–1.0) at/above which a derived ingredient↔compound
  # candidate is auto-promoted to a curated relationship; below it waits for review.
  candidate_promotion_threshold: 0.75,
  # Assay reagents / non-food chemicals that PubTator extracts as "chemicals" but
  # must never become dietary facts — excluded from derivation and purged on derive.
  # Matched case-insensitively against the exact compound name (use a plain list,
  # not ~w, so multi-word names like "Hydrogen Peroxide" are kept intact).
  non_dietary_compounds: [
    # antioxidant-assay reagents
    "DPPH",
    "ABTS",
    "TPTZ",
    "Trolox",
    "FRAP",
    "ORAC",
    "BHT",
    "BHA",
    # lab reagents / non-food chemicals / mis-annotations surfaced by PubTator
    "(3-(4,5-Dimethylthiazol-2-yl)-2,5-diphenyltetrazolium bromide)",
    "3,4-Methylenedioxyamphetamine",
    "Hydrogen Peroxide",
    "Ferric cation",
    "SDS",
    "LPS",
    "Hydrochloric Acid",
    "Water",
    "PS",
    "Gln-Glu",
    "sugar-acid",
    "oil",
    # solvents / process artifacts (appear in extraction & fermentation contexts,
    # not as intrinsic constituents)
    "Ethanol",
    "Methanol",
    "Acetone",
    "Chloroform",
    # non-specific class terms / measured targets, never a discrete dietary compound
    "Reactive Oxygen Species",
    "reactive oxygen species",
    "ROS",
    "Free Radicals",
    "Free Radical",
    "Heavy Metals",
    "Heavy Metal",
    "Reactive Nitrogen Species"
  ]

# Delivers notifications fired from the core `Notifications.emit/3` seam to the
# mobile channel + OS push. The web impl no-ops when the endpoint isn't running
# (core-only tests), so this is safe to set for every app in the umbrella.
config :mehungry, :notification_dispatcher, MehungryWeb.Api.NotificationDispatcher

config :mehungry, Oban,
  repo: Mehungry.Repo,
  # Pub/sub over Erlang process groups instead of the default single-connection
  # Postgres LISTEN/NOTIFY notifier. That dedicated notifier connection is a
  # single point of failure: a transient RDS blip/failover, an idle-connection
  # reap of its long-lived socket, or a burst of `insert_trigger` NOTIFYs from a
  # bulk job fan-out can freeze it, and every producer/plugin registered through
  # it then times out its 5s `:listen`/`:leader?` call and crashes together
  # (Oban-subtree restart storm). PG removes that socket entirely; leadership is
  # unaffected (Oban.Peers.Database, on the pool). Single-node deploy, so PG's
  # cluster-local scope is a non-issue. See oban_production_diagnostics.md.
  notifier: Oban.Notifiers.PG,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24},
    # Reap jobs left `executing` by a crash/OOM/node-kill back to `available` after
    # 30 min. Every real job (annotation batch of 10, a RecipeAgent tool loop) runs
    # well under this, so a job still `executing` past it is an orphan, not slow
    # work. Keeps a wedged science-pipeline chain from stalling ~24h post-restart.
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)},
    {Oban.Plugins.Cron,
     crontab: [
       # 1:30am UTC daily — refresh Instagram long-lived tokens before the 2am run
       {"30 1 * * *", Mehungry.ObanWorkers.InstagramTokenRefreshWorker},
       # 1:45am UTC daily — refresh Pinterest access tokens before the 2am run
       {"45 1 * * *", Mehungry.ObanWorkers.PinterestTokenRefreshWorker},
       # 2am UTC daily — generate recipes for the next day + schedule publish jobs
       {"0 2 * * *", Mehungry.ObanWorkers.DailyRecipeGenerationWorker},
       # every 10 min — resume any pipeline run (crawl/annotation/derivation) whose chain broke
       {"*/10 * * * *", Mehungry.ObanWorkers.PipelineWatchdogWorker},
       # 4am UTC Mondays — sync food products from Open Food Facts delta exports
       {"0 4 * * 1", Mehungry.ObanWorkers.OffDeltaSyncWorker},
       # hourly — release consultation card-holds before Stripe voids them (~7d)
       {"0 * * * *", Mehungry.ObanWorkers.AppointmentHoldExpiryWorker},
       # every 20 min — import connected nutritionists' Google Calendar busy times
       {"*/20 * * * *", Mehungry.ObanWorkers.GoogleCalendarBusyImportWorker}
     ]}
  ],
  queues: [
    # Total concurrency is capped at 13 job slots so it fits within the DB pool
    # (POOL_SIZE 18) with headroom for web/LiveView/Presence checkouts. Sized to
    # close the connection-pool starvation confirmed in prod (queue_time spiking
    # to ~10s) — see oban_production_diagnostics.md.
    default: 5,
    mailers: 3,
    ai_agents: 1,
    imports: 1,
    # Bulk USDA seed-file imports get their own slot so a full-bucket "Load
    # ingredients" run can't starve behind the long-running, self-resuming
    # science pipeline (literature crawl / PubTator / candidate derivation) that
    # shares the `:imports` queue. Capped to bound DB write pressure.
    seed_imports: 1,
    # Admin-triggered hashtag reconciliation sweep (one job per recipe). Its own
    # slot so a full-corpus resweep can't starve behind other background work.
    hashtag_reconcile: 1,
    # Admin-triggered derived-portion generation (one job per ingredient). Pure
    # DB work; its own slot so a full-table sweep can't starve `:default`/`:imports`.
    portion_generation: 1
  ]

config :swarm,
  distribution_strategy: Swarm.Distribution.StaticQuorumRing,
  static_quorum_size: 1

config :mehungry_web,
  ecto_repos: [Mehungry.Repo],
  generators: [context_app: :mehungry]

# Supported UI/content locales, carried as the leading URL path segment
# (`/en/…`, `/el/…`). `default` is used for bare `/`, unknown locales, and the
# Gettext fallback. Single source of truth read by `MehungryWeb.Locale`.
config :mehungry_web, :locales,
  supported: ["en", "el"],
  default: "en"

# Gettext's process-locale default when nothing sets it (matches :locales default).
config :gettext, :default_locale, "en"

# Configures the endpoint
# secret_key_base is intentionally absent here — set via SECRET_KEY_BASE env var
# in runtime.exs for prod, and in dev.exs / test.exs for local environments.
config :mehungry_web, MehungryWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: MehungryWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Mehungry.PubSub,
  live_view: [signing_salt: "l1ra29uq"],
  aws_key_id: nil,
  aws_secret: nil,
  aws_bucket: nil

config :beam_scope,
  # Point at your host's Phoenix.PubSub server (BeamScope does NOT start it in embedded mode).
  pubsub: Mehungry.PubSub,

  # Default synchronization strategy: gossip compact snapshots over PubSub (ADR-0005).
  sync: BeamScope.Synchronization.SnapshotGossip,
  sync_interval: :timer.seconds(1),
  node_ttl: :timer.seconds(5),
  providers: [{BeamScope.Provider.Phoenix, :phoenix}],

  # Top-N bound for the Process/ETS providers (largest mailboxes / memory / tables).
  top_n: 5

config :ex_aws,
  access_key_id: nil,
  secret_access_key: nil,
  region: "eu-central-1"

# Object storage. `backend` selects which `Mehungry.Storage` implementation is
# used app-wide: `:supabase` (Supabase Storage REST, the default and the only
# backend used in production) or `:s3` (legacy AWS, via `Mehungry.S3`). The
# effective backend is set from STORAGE_BACKEND at runtime (see
# config/runtime.exs); Supabase values are nil here and filled from env there.
config :mehungry, :storage,
  backend: :supabase,
  supabase_url: nil,
  service_role_key: nil,
  bucket: "media"

config :ueberauth, Ueberauth,
  providers: [
    facebook:
      {Ueberauth.Strategy.Facebook,
       [
         profile_fields: "name,email,first_name,last_name, picture",
         scope: "pages_manage_engagement, pages_manage_posts, pages_read_engagement "
       ]},
    instagram:
      {Ueberauth.Strategy.Instagram,
       [
         default_scope: "instagram_business_basic,instagram_business_content_publish"
       ]},
    pinterest:
      {Ueberauth.Strategy.Pinterest,
       [
         default_scope: "boards:read,boards:write,pins:read,pins:write,user_accounts:read"
       ]},
    google: {Ueberauth.Strategy.Google, []},
    identity:
      {Ueberauth.Strategy.Identity,
       [
         callback_methods: ["POST"],
         uid_field: :username,
         nickname_field: :username
       ]}
  ]

# OAuth credentials are nil at compile time.
# Set in dev.exs for local development and in runtime.exs for production.
config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: nil,
  client_secret: nil

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: nil,
  client_secret: nil

config :ueberauth, Ueberauth.Strategy.Instagram.OAuth,
  client_id: nil,
  client_secret: nil

config :ueberauth, Ueberauth.Strategy.Pinterest.OAuth,
  client_id: nil,
  client_secret: nil

config :esbuild,
  version: "0.17.11",
  mehungry_web: [
    args: [
      "js/app.js",
      "--bundle",
      "--target=es2017",
      "--outdir=../priv/static/js",
      "--external:/fonts/*",
      "--external:/images/*",
      "--external:/favicons/*"
    ],
    cd: Path.expand("../apps/mehungry_web/assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.0",
  mehungry_web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/css/app.css

    ),
    cd: Path.expand("../apps/mehungry_web/assets/", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# PromEx — Prometheus metrics collection (served at the token-guarded GET /metrics
# via MehungryWeb.MetricsController). Grafana dashboard upload and the standalone
# metrics HTTP server are disabled; we scrape through our own endpoint.
grafana_config =
  case System.get_env("GRAFANA_AUTH_TOKEN") do
    nil ->
      :disabled

    token ->
      [
        host: "http://localhost:3000",
        auth_token: token,
        upload_dashboards_on_start: true,
        folder_name: "MeHungry",
        annotate_app_lifecycle: false
      ]
  end

config :mehungry_web, MehungryWeb.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: grafana_config,
  metrics_server: :disabled

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
