defmodule Mehungry.Repo do
  use Ecto.Repo,
    otp_app: :mehungry,
    adapter: Ecto.Adapters.Postgres
end
