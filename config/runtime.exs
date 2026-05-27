import Config

# AWS credentials and bucket are read at runtime so that values exported
# in the shell (e.g. phxserver.sh) are picked up on every startup rather
# than being baked in at compile time.
config :mehungry,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY", ""),
  stripe_secret_key: System.get_env("STRIPE_SECRET_KEY", ""),
  stripe_webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET", ""),
  stripe_pro_price_id: System.get_env("STRIPE_PRO_PRICE_ID", ""),
  stripe_pro_yearly_price_id: System.get_env("STRIPE_PRO_YEARLY_PRICE_ID", "")

config :mehungry_web,
  aws_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret: System.get_env("AWS_SECRET_ACCESS_KEY"),
  aws_bucket: System.get_env("AWS_ASSETS_BUCKET_NAME")

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: "eu-central-1"

if config_env() == :prod do
  config :mehungry, Mehungry.Mailer,
    adapter: Swoosh.Adapters.AmazonSES,
    region: System.get_env("AWS_SES_REGION", "eu-central-1"),
    access_key: System.get_env("AWS_ACCESS_KEY_ID"),
    secret: System.get_env("AWS_SECRET_ACCESS_KEY")

  config :swoosh, :api_client, Swoosh.ApiClient.Hackney
end
