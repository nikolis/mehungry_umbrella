defmodule Mehungry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    Mehungry.Telemetry.ActionContext.attach()

    children = [
      # Start the Ecto repository
      Mehungry.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Mehungry.PubSub},
      {Oban, Application.fetch_env!(:mehungry, Oban)},
      # Start a worker by calling: Mehungry.Worker.start_link(arg)
      # {Mehungry.Worker, arg}
      # Supervisor.child_spec({Cachex, name: :recipe_cache}, id: :recipe_cache)
      # Supervisor.child_spec({Cachex, name: :create_recipe_cache}, id: :create_recipe_cache)
      # {Cachex, [:recipe_cache, [limit: 300]], id: :recipes_cache_worker}  # with custom options
      %{id: :recipes_cache, start: {Cachex, :start_link, [:recipes_cache, [limit: 150]]}},
      %{id: :cache_user_tokens, start: {Cachex, :start_link, [:cache_user_tokens]}},
      %{id: :geo_cache, start: {Cachex, :start_link, [:geo_cache, [limit: 5000]]}},
      # Negative cache for Open Food Facts barcode lookups (respects OFF's 100 req/min limit)
      %{id: :off_lookup_cache, start: {Cachex, :start_link, [:off_lookup_cache, [limit: 1000]]}},
      Mehungry.Telemetry.MetricsBuffer,
      Mehungry.Telemetry.ErrorTracker,
      {Task.Supervisor, name: Mehungry.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Mehungry.Supervisor)
  end
end
