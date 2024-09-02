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

config :mehungry_web,
  ecto_repos: [Mehungry.Repo],
  generators: [context_app: :mehungry]

# Configures the endpoint
config :mehungry_web, MehungryWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "iH7KE2sUcWxfSctkWBtzxcSkJlSKZaVWP/hDKC8Hg3gCkGYZcXhIZLrEkzw/Ddq3",
  render_errors: [view: MehungryWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Mehungry.PubSub,
  live_view: [signing_salt: "l1ra29uq"],
  aws_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret: System.get_env("AWS_SECRET_ACCESS_KEY"),
  aws_bucket: System.get_env("AWS_ASSETS_BUCKET_NAME")

config :ueberauth, Ueberauth,
  providers: [
    facebook:
      {Ueberauth.Strategy.Facebook, [profile_fields: "name,email,first_name,last_name, picture"]},
    google: {Ueberauth.Strategy.Google, []},
    identity:
      {Ueberauth.Strategy.Identity,
       [
         callback_methods: ["POST"],
         uid_field: :username,
         nickname_field: :username
       ]}
  ]

config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
  client_id: System.get_env("FACEBOOK_CLIENT_ID"),
  client_secret: System.get_env("FACEBOOK_CLIENT_SECRET") 


config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")


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
