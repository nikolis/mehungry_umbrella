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

config :mehungry, Mehungry.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, false

config :mehungry, Oban,
  repo: Mehungry.Repo,
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24}
  ],
  queues: [
    default: 10,
    mailers: 5
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
         default_scope:
           "instagram_business_basic,instagram_business_content_publish"
       ]},
    pinterest:
      {Ueberauth.Strategy.Pinterest,
       [
         default_scope: "boards:read,pins:write,user_accounts:read"
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
