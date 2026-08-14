defmodule MehungryLocalAi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # The Bumblebee extractive-QA serving (EXLA/CPU). Loading is slow, so it does
      # NOT start at boot by default — its child spec :ignores unless
      # `:start_qa` is true. `mix local_ai.extract` loads it on demand via
      # MehungryLocalAi.QA.ensure_started/0 and reuses it across the batch.
      MehungryLocalAi.QA
    ]

    opts = [strategy: :one_for_one, name: MehungryLocalAi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
