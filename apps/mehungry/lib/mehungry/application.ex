defmodule Mehungry.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Mehungry.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: Mehungry.PubSub}
      # Start a worker by calling: Mehungry.Worker.start_link(arg)
      # {Mehungry.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Mehungry.Supervisor)
  end
end
