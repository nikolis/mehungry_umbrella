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
  live_view: [signing_salt: "l1ra29uq"]

config :tailwind, version: "3.1.8", default: [
  args: ~w(
    --config=tailwind.config.js
    --input=css/app.css
    --output=../apps/mehungry_web/priv/static/assets/app.css
  ),
  cd: Path.expand("../assets", __DIR__)
]  

config :mehungry_api, MehungryApi.Guardian,
  issuer: "mehungry_api",
  secret_key: "xqo0BfDpsWTY/ZDz/+nmsbdLFLfZEmU3qXhJzdtc3qS7GZyji91GLgE15nYoVbxt"

# Configures the endpoint
config :mehungry_api, MehungryApi.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "iH7KE2sUcWxfd3dkWBtzxcSkJlSKZaVWP/hDKC8Hg3gCkGYZcXhIZLrEkzw/Ddq3",
  render_errors: [view: MehungryApi.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: Mehungry.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
