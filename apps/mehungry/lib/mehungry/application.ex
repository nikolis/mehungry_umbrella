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
      {Phoenix.PubSub, name: Mehungry.PubSub},
      # Start a worker by calling: Mehungry.Worker.start_link(arg)
      # {Mehungry.Worker, arg}
      # Supervisor.child_spec({Cachex, name: :recipe_cache}, id: :recipe_cache)
      # Supervisor.child_spec({Cachex, name: :create_recipe_cache}, id: :create_recipe_cache)
      # {Cachex, [:recipe_cache, [limit: 300]], id: :recipes_cache_worker}  # with custom options
      %{id: :recipes_cache, start: {Cachex, :start_link, [:recipes_cache, [limit: 150]]}},
      %{id: :cache_user_tokens, start: {Cachex, :start_link, [:cache_user_tokens]}}

      # Supervisor.Spec.worker(Cachex, [:recipes_cache, [limit: 500]], id: :recipes_cache)
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Mehungry.Supervisor)
  end
end
