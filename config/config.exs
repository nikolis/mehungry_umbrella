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

# Base URL + shared-secret bearer token the non-deployed mehungry_local_ai service
# uses to reach the local-AI REST API. Overridden in runtime.exs from env vars.
config :mehungry_local_ai, server_base_url: "http://localhost:4000"

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
# or a 429 is returned. See docs/food.md / the worker moduledoc.
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
    "oil"
  ]

config :mehungry, Oban,
  repo: Mehungry.Repo,
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
       # 2am UTC daily — generate recipes for the next day + schedule publish jobs
       {"0 2 * * *", Mehungry.ObanWorkers.DailyRecipeGenerationWorker},
       # 3am UTC daily — prune telemetry snapshots older than 30 days
       {"0 3 * * *", Mehungry.ObanWorkers.TelemetryPrunerWorker},
       # every 10 min — resume any pipeline run (crawl/annotation/derivation) whose chain broke
       {"*/10 * * * *", Mehungry.ObanWorkers.PipelineWatchdogWorker},
       # 4am UTC Mondays — sync food products from Open Food Facts delta exports
       {"0 4 * * 1", Mehungry.ObanWorkers.OffDeltaSyncWorker}
     ]}
  ],
  queues: [
    default: 10,
    mailers: 5,
    ai_agents: 2,
    imports: 2
  ]

config :swarm,
  distribution_strategy: Swarm.Distribution.StaticQuorumRing,
  static_quorum_size: 1

config :mehungry_web,
  ecto_repos: [Mehungry.Repo],
  generators: [context_app: :mehungry]

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

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
