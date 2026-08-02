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
config :mehungry, :off_client, Mehungry.FoodData.OpenFoodFacts.ClientStub

# PubChem PUG REST is stubbed per-test via the `:pubchem_http_adapter` seam; pin a
# deterministic base URL so no test can accidentally reach the real API.
config :mehungry, :pubchem_base_url, "http://pubchem.test/rest/pug"
# Lift the local 5 req/s throttle so the shared rate-limit window never trips
# across fast async tests (retry/throttle is exercised via stubbed HTTP 503s).
config :mehungry, :pubchem_rate_limit, 1_000_000

# NCBI Entrez E-utilities is stubbed per-test via the `:entrez_http_adapter` seam;
# pin a deterministic base URL and lift the local rate throttle for fast tests.
config :mehungry, :entrez_base_url, "http://entrez.test/entrez/eutils"
config :mehungry, :entrez_rate_limit, 1_000_000

# NCBI PubTator3 is stubbed per-test via the `:pubtator_http_adapter` seam; pin a
# deterministic base URL and lift the local rate throttle for fast tests.
config :mehungry, :pubtator_base_url, "http://pubtator.test/research/pubtator3-api"
config :mehungry, :pubtator_rate_limit, 1_000_000

# Instagram Graph API client + social media publisher are stubbed in tests
config :mehungry, :instagram_client, Mehungry.Social.Instagram.ClientStub
config :mehungry, :social_media_publisher, Mehungry.Social.PublisherStub

# Taxonomy classifier is stubbed in tests — no AI/API calls
config :mehungry, :taxonomy_classifier, Mehungry.AI.TaxonomyClassifierStub

# S3 seed-file fetcher is stubbed in tests — no S3/network calls
config :mehungry, :seed_file_fetcher, Mehungry.FoodData.Usda.SeedFileFetcherStub

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

# A dummy token so the local-AI REST API guard is exercisable in tests.
config :mehungry, :local_ai_api_token, "test-local-ai-token"

# Never load the Bumblebee QA model in the test suite — extraction falls back to the
# rule-based path (MehungryLocalAi.QA.available? is false).
config :mehungry_local_ai, start_qa: false
