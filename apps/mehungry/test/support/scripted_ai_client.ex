defmodule Mehungry.AI.ScriptedClient do
  @moduledoc """
  Test stand-in for `Mehungry.AI.Client` (the `:ai_client` seam): replays a
  scripted list of Messages-API responses, one per `request/1`, so an agent's
  tool-use loop can be driven end to end without the network.

      ScriptedClient.script([
        ScriptedClient.tool_use("search_recipes", %{"query" => "bowl"}),
        fn -> ScriptedClient.tool_use("submit_plan", %{"entries" => entries()}) end,
        ScriptedClient.end_turn("done")
      ])

  A step may be a zero-arity function, evaluated when reached (so it can read
  state an earlier tool call produced). Running past the script returns an error.
  """

  @key {__MODULE__, :script}

  def script(steps) do
    :persistent_term.put(@key, steps)
    Application.put_env(:mehungry, :ai_client, __MODULE__)
  end

  def reset do
    :persistent_term.erase(@key)
    Application.delete_env(:mehungry, :ai_client)
  end

  def request(_params) do
    case :persistent_term.get(@key, []) do
      [] ->
        {:error, "script exhausted"}

      [step | rest] ->
        :persistent_term.put(@key, rest)
        if is_function(step, 0), do: step.(), else: step
    end
  end

  def tool_use(name, input) do
    {:ok,
     %{
       stop_reason: "tool_use",
       content: [
         %{
           "type" => "tool_use",
           "id" => "tu_#{System.unique_integer([:positive])}",
           "name" => name,
           "input" => input
         }
       ],
       usage: %{input_tokens: 0, output_tokens: 0}
     }}
  end

  def end_turn(text) do
    {:ok,
     %{
       stop_reason: "end_turn",
       content: [%{"type" => "text", "text" => text}],
       usage: %{input_tokens: 0, output_tokens: 0}
     }}
  end
end
