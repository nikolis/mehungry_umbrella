defmodule Mehungry.AI.Eval.TokenMeter do
  @moduledoc """
  Tallies Anthropic token usage during an eval run by listening to the
  `[:mehungry, :ai, :client, :request, :stop]` telemetry `AI.Client` emits per
  API call. Lets the meal-plan eval report its own token cost.

  Usage:

      meter = TokenMeter.start()
      # ... run the agent ...
      totals = TokenMeter.stop(meter)   # %{input:, output:, calls:, by_model:}
  """

  @event [:mehungry, :ai, :client, :request, :stop]

  def start do
    # Unlinked on purpose: `on_exit` runs in a separate process after the test
    # process (and anything linked to it) has died, so a linked agent would be
    # gone by the time we read totals.
    {:ok, agent} =
      Agent.start(fn -> %{input: 0, output: 0, calls: 0, by_model: %{}} end)

    id = {__MODULE__, make_ref()}
    :telemetry.attach(id, @event, &__MODULE__.handle/4, agent)
    {agent, id}
  end

  def handle(_event, measurements, metadata, agent) do
    i = measurements[:input_tokens] || 0
    o = measurements[:output_tokens] || 0
    model = metadata[:model] || "unknown"

    Agent.update(agent, fn s ->
      by_model =
        Map.update(s.by_model, model, {i, o, 1}, fn {bi, bo, bc} ->
          {bi + i, bo + o, bc + 1}
        end)

      %{s | input: s.input + i, output: s.output + o, calls: s.calls + 1, by_model: by_model}
    end)
  end

  def stop({agent, id}) do
    :telemetry.detach(id)
    totals = Agent.get(agent, & &1)
    Agent.stop(agent)
    totals
  end

  @doc "A readable multi-line usage report."
  def format(%{input: input, output: output, calls: calls, by_model: by_model}) do
    per_model =
      Enum.map_join(by_model, "\n", fn {model, {i, o, c}} ->
        "    #{model}: #{c} calls, #{i} in / #{o} out tokens"
      end)

    """
    token usage: #{calls} API calls, #{input} input + #{output} output = #{input + output} total tokens
    #{per_model}
    """
  end
end
