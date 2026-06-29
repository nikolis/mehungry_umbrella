defmodule Mehungry.Repo do
  use Ecto.Repo,
    otp_app: :mehungry,
    adapter: Ecto.Adapters.Postgres

  use Paginator
end

# Register the pgvector Postgrex extension so vector columns round-trip correctly.
Postgrex.Types.define(
  Mehungry.PostgrexTypes,
  [Pgvector.Extensions.Vector] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
