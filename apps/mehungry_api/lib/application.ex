defmodule MehungryApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    IO.inspect("Starting the mehungry api application from /apps/mehungry_api/application.ex")
    children = [
      # Start the Telemetry supervisor
      # Start the Endpoint (http/https)
      MehungryApi.Endpoint 
      # Start a worker by calling: MehungryWeb.Worker.start_link(arg)
      # {MehungryWeb.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MehungryApi.Supervisor]
    start_link = Supervisor.start_link(children, opts)
    IO.inspect(start_link, label: "Start link output")
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    MehungryApi.Endpoint.config_change(changed, removed)
    :ok
  end
end
