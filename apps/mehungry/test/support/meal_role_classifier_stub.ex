defmodule Mehungry.AI.RecipeMealRoleClassifierStub do
  @moduledoc """
  Test stand-in for `Mehungry.AI.RecipeMealRoleClassifier` (wired via the
  `:meal_role_classifier` config key in `config/test.exs`) — no API calls.

  Tests control the result through app config (so they must be `async: false`):

      Application.put_env(:mehungry, :meal_role_classifier_stub, fn recipes ->
        send(test_pid, {:classify, recipes})
        {:ok, %{recipe.id => [%{role: "main", confidence: 0.9}]}}
      end)
      on_exit(fn -> Application.delete_env(:mehungry, :meal_role_classifier_stub) end)
  """

  @behaviour Mehungry.AI.RecipeMealRoleClassifierBehaviour

  @impl true
  def classify(recipes) do
    case Application.get_env(:mehungry, :meal_role_classifier_stub) do
      nil -> {:ok, %{}}
      fun -> fun.(recipes)
    end
  end
end
