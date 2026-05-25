import Config

# AWS credentials and bucket are read at runtime so that values exported
# in the shell (e.g. phxserver.sh) are picked up on every startup rather
# than being baked in at compile time.
config :mehungry_web,
  aws_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  aws_secret: System.get_env("AWS_SECRET_ACCESS_KEY"),
  aws_bucket: System.get_env("AWS_ASSETS_BUCKET_NAME")

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY"),
  region: "eu-central-1"
