defmodule Mehungry.Food.CompoundPlausibilityStub do
  @moduledoc """
  Test stand-in for `Mehungry.Food.CompoundPlausibility` (wired via the
  `:compound_plausibility_judge` config key in `config/test.exs`) so candidate
  derivation makes no AI/API calls.

  Default verdict is `:plausible` (so existing tests keep auto-promoting). Tests
  override the result and observe calls through app config:

      Application.put_env(:mehungry, :compound_plausibility_stub, fn _species, compound, _studies ->
        send(test_pid, {:judged, compound.name})
        {:ok, %{verdict: :implausible, reason: "solvent, not a constituent"}}
      end)
      on_exit(fn -> Application.delete_env(:mehungry, :compound_plausibility_stub) end)
  """

  @behaviour Mehungry.Food.CompoundPlausibilityBehaviour

  @impl true
  def judge(species, compound, studies) do
    case Application.get_env(:mehungry, :compound_plausibility_stub) do
      nil -> {:ok, %{verdict: :plausible, reason: "stub default"}}
      fun -> fun.(species, compound, studies)
    end
  end
end
