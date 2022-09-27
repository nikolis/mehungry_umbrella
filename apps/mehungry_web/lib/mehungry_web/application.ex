defmodule MehungryWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    IO.inspect("Strting application mehungry_WEB you know the drill")

    children = [
      # Start the Telemetry supervisor
      MehungryWeb.Telemetry,
      # Start the Endpoint (http/https)
      MehungryWeb.Endpoint,
      # Start a worker by calling: MehungryWeb.Worker.start_link(arg)
      # {MehungryWeb.Worker, arg}
      {MehungryWeb.OnlineRecommender, []},
      {Cachex, name: :users}
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
