# :ai_eval tests call the live Anthropic API (cost + key). Excluded by default;
# run with `mix test --only ai_eval`.
ExUnit.start(exclude: [:ai_eval])
Ecto.Adapters.SQL.Sandbox.mode(Mehungry.Repo, :manual)
