defmodule Mehungry.AI.TaxonomyClassifierStub do
  @moduledoc """
  Test stand-in for `Mehungry.AI.TaxonomyClassifier` (wired via the
  `:taxonomy_classifier` config key in `config/test.exs`) so worker tests make
  no API calls.

  Tests control the result and observe calls through app config:

      Application.put_env(:mehungry, :taxonomy_classifier_stub, fn ingredients, leaves ->
        send(test_pid, {:classify, ingredients, leaves})
        {:ok, assignments}
      end)
      on_exit(fn -> Application.delete_env(:mehungry, :taxonomy_classifier_stub) end)
  """

  @behaviour Mehungry.AI.TaxonomyClassifierBehaviour

  @impl true
  def classify(ingredients, leaves) do
    case Application.get_env(:mehungry, :taxonomy_classifier_stub) do
      nil -> {:ok, []}
      fun -> fun.(ingredients, leaves)
    end
  end
end
