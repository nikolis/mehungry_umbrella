defmodule MehungryWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  import Cachex.Spec

  @env Mix.env()

  def start(_type, _args) do
    children = [
      # PromEx owns the Prometheus scrape path — start it before the Endpoint so
      # its telemetry handlers are attached before the first request.
      MehungryWeb.PromEx,
      # Manually Crated Presence Model
      MehungryWeb.Presence,
      # LiveDashboard metric definitions + telemetry poller.
      MehungryWeb.Telemetry,
      # Start the Endpoint (http/https)

      MehungryWeb.Endpoint,
      {Task.Supervisor, name: MehungryWeb.TaskSupervisor},
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

    children =
      if @env != :test do
        # Start libcluster
        [
          {Cluster.Supervisor,
           [Application.get_env(:libcluster, :topologies), [name: Mehungry.ClusterSupervisor]]}
        ] ++
          children
      else
        children
      end

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
