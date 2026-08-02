defmodule MehungryLocalAi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # The Bumblebee extractive-QA serving (EXLA/CPU). Loading is slow, so it's
      # started once when the app boots and reused across the batch.
      MehungryLocalAi.QA
    ]

    opts = [strategy: :one_for_one, name: MehungryLocalAi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
