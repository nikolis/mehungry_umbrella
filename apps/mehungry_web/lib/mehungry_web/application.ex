defmodule MehungryWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  import Cachex.Spec

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      # MehungryWeb.Telemetry,
      # Manually Crated Presence Model
      MehungryWeb.Presence,
      # MehungryWeb.Telemetry,
      # Start the Endpoint (http/https)
      MehungryWeb.Endpoint,
      # Start a worker by calling: MehungryWeb.Worker.start_link(arg)
      # {MehungryWeb.Worker, arg}
      # {MehungryWeb.OnlineRecommender, []},
      %{
        id: :create_recipe_cache,
        start:
          {Cachex, :start_link,
           [
             :create_recipe_cache,
             [expiration: expiration(default: :timer.hours(1), interval: :timer.hours(1))]
           ]}
      }
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MehungryWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MehungryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
