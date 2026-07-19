import Config
config :mehungry, Oban, testing: :manual

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mehungry, Mehungry.Repo,
  username: "postgres",
  password: "postgres",
  database: "mehungry_server_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  types: Mehungry.PostgrexTypes

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mehungry_web, MehungryWeb.Endpoint,
  http: [port: 4002],
  server: true,
  secret_key_base: String.duplicate("a", 64)

config :mehungry, :sql_sandbox, true

# Open Food Facts client is stubbed in tests — no network calls
config :mehungry, :off_client, Mehungry.OpenFoodFacts.ClientStub

# Instagram Graph API client + social media publisher are stubbed in tests
config :mehungry, :instagram_client, Mehungry.Social.Instagram.ClientStub
config :mehungry, :social_media_publisher, Mehungry.Social.PublisherStub

# Chrome
# default
config :wallaby,
  opt_app: :mehungry_web,
  chromedriver: [headless: System.get_env("CI") == "true"],
  driver: Wallaby.Chrome

# Selenium
# config :wallaby, driver: Wallaby.Selenium

config :libcluster, topologies: []

# Print only warnings and errors during test
config :logger, level: :warning
