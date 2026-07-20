import Config

# AWS credentials and bucket are read at runtime so that values exported
# in the shell (e.g. phxserver.sh) are picked up on every startup rather
# than being baked in at compile time.
config :mehungry,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY", ""),
  fdc_api_key: System.get_env("FDC_API_KEY", ""),
  openai_api_key: System.get_env("OPENAI_API_KEY", ""),
  stripe_secret_key: System.get_env("STRIPE_SECRET_KEY", ""),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET", ""),
  stripe_pro_price_id: System.get_env("STRIPE_PRO_PRICE_ID", ""),
  stripe_pro_yearly_price_id: System.get_env("STRIPE_PRO_YEARLY_PRICE_ID", ""),
  stripe_nutritionist_price_id: System.get_env("STRIPE_NUTRITIONIST_PRICE_ID", ""),
  stripe_nutritionist_yearly_price_id: System.get_env("STRIPE_NUTRITIONIST_YEARLY_PRICE_ID", ""),
  # Cloudflare Turnstile CAPTCHA on the registration form. When the secret key
  # is unset (dev/test), verification is skipped so local signups still work.
  turnstile_site_key: System.get_env("TURNSTILE_SITE_KEY"),
  turnstile_secret_key: System.get_env("TURNSTILE_SECRET_KEY")

# Pinterest environment switch: PINTEREST_ENV=live hits the real API,
# anything else (including unset) stays on the sandbox. Sandbox and live
# tokens are not interchangeable — accounts must be reconnected after
# switching. The OAuth token exchange and user_account lookup derive their
# host from this same key.
pinterest_api_base =
  case System.get_env("PINTEREST_ENV", "sandbox") do
    "live" -> "https://api.pinterest.com/v5"
    _ -> "https://api-sandbox.pinterest.com/v5"
  end

config :mehungry, pinterest_api_base: pinterest_api_base

# Open Food Facts (no API key; OFF requires an identifying User-Agent contact)
config :mehungry,
  off_base_url: System.get_env("OFF_BASE_URL", "https://world.openfoodfacts.org"),
  off_static_url: System.get_env("OFF_STATIC_URL", "https://static.openfoodfacts.org"),
  off_dump_dir: System.get_env("OFF_DUMP_DIR"),
  off_contact_email: System.get_env("OFF_CONTACT_EMAIL", "nikolisgal@gmail.com")

config :mehungry_web,
  aws_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret: System.get_env("AWS_SECRET_ACCESS_KEY"),
  aws_bucket: System.get_env("AWS_ASSETS_BUCKET_NAME"),
  ga_measurement_id: System.get_env("GA_MEASUREMENT_ID", "G-JPGJG6GCSK")

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: "eu-central-1"

if config_env() == :prod do
  config :mehungry, Mehungry.Mailer,
    adapter: Swoosh.Adapters.AmazonSES,
    region: System.get_env("AWS_SES_REGION", "eu-central-1"),
    access_key: System.fetch_env!("AWS_ACCESS_KEY_ID"),
    secret: System.fetch_env!("AWS_SECRET_ACCESS_KEY")

  config :swoosh, :api_client, Swoosh.ApiClient.Hackney
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE environment variable is missing"

  config :mehungry_web, MehungryWeb.Endpoint,
    secret_key_base: secret_key_base,
    url: [scheme: "https", host: "www.mehungry.com", port: 443]

  config :ueberauth, Ueberauth.Strategy.Facebook.OAuth,
    client_id: System.get_env("FACEBOOK_CLIENT_ID"),
    client_secret: System.get_env("FACEBOOK_CLIENT_SECRET")

  config :ueberauth, Ueberauth.Strategy.Google.OAuth,
    client_id: System.get_env("GOOGLE_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

  config :ueberauth, Ueberauth.Strategy.Instagram.OAuth,
    client_id: System.get_env("INSTAGRAM_CLIENT_ID"),
    client_secret: System.get_env("INSTAGRAM_CLIENT_SECRET")

  config :ueberauth, Ueberauth.Strategy.Pinterest.OAuth,
    client_id: System.get_env("PINTEREST_CLIENT_ID"),
    client_secret: System.get_env("PINTEREST_CLIENT_SECRET")
end

if config_env() == :prod do
  database_url =
    case System.get_env("DATABASE_URL") do
      nil ->
        raise "DATABASE_URL environment variable is missing"

      value ->
        value
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
  query_args = ["SET pg_trgm.similarity_threshold = 0.3", []]

  config :mehungry, Mehungry.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    after_connect: {Postgrex, :query!, query_args},
    types: Mehungry.PostgrexTypes
end
