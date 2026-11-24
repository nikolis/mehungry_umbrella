defmodule Mehungry.AI.RecipeTimeEstimatorStub do
  @moduledoc """
  Test stand-in for `Mehungry.AI.RecipeTimeEstimator` (wired via the
  `:recipe_time_estimator` config key in `config/test.exs`) — no API calls. Tests set
  `Application.put_env(:mehungry, :recipe_time_estimator_stub, fn recipes -> ... end)`
  (so they must be `async: false`).
  """

  @behaviour Mehungry.AI.RecipeTimeEstimator

  @impl true
  def estimate(recipes) do
    case Application.get_env(:mehungry, :recipe_time_estimator_stub) do
      nil -> {:ok, %{}}
      fun -> fun.(recipes)
    end
  end
end
