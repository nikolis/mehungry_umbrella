import Config

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
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mehungry_web, MehungryWeb.Endpoint,
  http: [port: 4000],
  server: true

config :mehungry, :sql_sandbox, true

# Chrome
# default
config :wallaby, opt_app: :mehungry_web, chromedriver: [headless: false], driver: Wallaby.Chrome

# Selenium
# config :wallaby, driver: Wallaby.Selenium

# Print only warnings and errors during test
config :logger, level: :warning
