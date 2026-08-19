defmodule Mehungry.AI.Agent do
  @moduledoc """
  Generic tool-use loop for Anthropic-powered agents.

  Runs a conversation with the AI until `stop_reason` is `"end_turn"` or
  `max_iterations` is reached. On each `"tool_use"` stop it dispatches the
  requested tool calls to a caller-supplied handler function and appends the
  results as the next user turn, then continues the loop.

  ## Accumulator

  The `context` argument is a threaded **accumulator**: the handler receives the
  current accumulator and returns `{result, new_acc}`. `result` is the
  JSON-encodable value fed back to the model as the tool result; `new_acc` is
  carried forward to the next tool call and the next iteration. `run/6` returns
  the final accumulator alongside the text, so a handler can hand real state
  (validated output, provenance sets) back to the caller **without** stashing it
  in the process dictionary.

  ## Usage

      tool_defs = [
        %{
          name: "search_ingredient",
          description: "Search for an ingredient in the database",
          input_schema: %{
            type: "object",
            properties: %{name: %{type: "string", description: "ingredient name"}},
            required: ["name"]
          }
        }
      ]

      handler = fn
        "search_ingredient", %{"name" => name}, acc ->
          results = Mehungry.Food.IngredientSearch.search(name) |> Enum.take(5)
          {Enum.map(results, & &1.name), Map.put(acc, :last_search, name)}

        _, _, acc ->
          {%{error: "unknown tool"}, acc}
      end

      {:ok, text, acc} = Mehungry.AI.Agent.run(system, user_msg, tool_defs, handler, %{})
  """

  require Logger

  @default_max_iterations 10

  @type tool_def :: %{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }

  @type tool_handler :: (String.t(), map(), acc :: any() -> {result :: any(), acc :: any()})

  @doc """
  Runs the agent loop.

  Arguments:
    - `system`       — system prompt string
    - `user_message` — initial user turn (string or list of content blocks)
    - `tool_defs`    — list of `%{name, description, input_schema}` tool maps
    - `handler`      — `fn(tool_name, tool_input, acc) -> {result, new_acc}`
                       `result` must be JSON-encodable; `new_acc` is threaded on
    - `context`      — the initial accumulator, threaded through every handler call
    - `opts`         — keyword list:
                         `:max_iterations` (default #{@default_max_iterations})
                         `:model`          (overrides client default)
                         `:max_tokens`     (overrides client default)
                         `:telemetry_metadata` — map merged into every telemetry
                            event's metadata (e.g. `%{agent: "recipe"}`) so the
                            Prometheus AI plugin can tag metrics per agent

  Returns `{:ok, text, final_acc}` or `{:error, reason}`.

  ## Telemetry

  Emits `[:mehungry, :ai, :agent, :run, :start | :stop]` (measurements
  `duration`, `iterations`; metadata `agent`, `model`, `outcome` — one of
  `end_turn` / `max_iterations` / `max_tokens` / `error`) and, per tool call,
  `[:mehungry, :ai, :agent, :tool, :start | :stop]` (metadata `tool`, `agent`,
  `status`). See `MehungryWeb.PromEx.AiPlugin`.
  """
  @spec run(String.t(), any(), [tool_def()], tool_handler(), any(), keyword()) ::
          {:ok, String.t(), any()} | {:error, term()}
  def run(system, user_message, tool_defs, handler, context, opts \\ []) do
    request_base =
      %{system: system, tools: tool_defs}
      |> put_if_present(:model, Keyword.get(opts, :model))
      |> put_if_present(:max_tokens, Keyword.get(opts, :max_tokens))

    messages = [%{role: "user", content: user_message}]
    max_iter = Keyword.get(opts, :max_iterations, @default_max_iterations)

    meta =
      opts
      |> Keyword.get(:telemetry_metadata, %{})
      |> Map.put_new(:agent, "unknown")
      |> Map.put(:model, Keyword.get(opts, :model, "default"))

    start = System.monotonic_time()
    :telemetry.execute([:mehungry, :ai, :agent, :run, :start], %{system_time: System.system_time()}, meta)

    {result, iterations} = loop(messages, handler, context, request_base, 0, max_iter, meta)

    :telemetry.execute(
      [:mehungry, :ai, :agent, :run, :stop],
      %{duration: System.monotonic_time() - start, iterations: iterations},
      Map.put(meta, :outcome, outcome(result))
    )

    result
  end

  defp outcome({:ok, _text, _acc}), do: "end_turn"
  defp outcome({:error, :max_iterations_reached}), do: "max_iterations"
  defp outcome({:error, :max_tokens_reached}), do: "max_tokens"
  defp outcome({:error, _}), do: "error"

  # ── loop ─────────────────────────────────────────────────────────────────────

  # Returns `{result, iterations}` so run/6 can report loop depth as a telemetry
  # measurement (are we brushing the max_iterations ceiling?).
  defp loop(_messages, _handler, _acc, _req, max, max, _meta) do
    Logger.warning("AI.Agent: reached max_iterations (#{max}), stopping")
    {{:error, :max_iterations_reached}, max}
  end

  defp loop(messages, handler, acc, req_base, iteration, max_iter, meta) do
    request = Map.put(req_base, :messages, messages)

    case client().request(request) do
      {:ok, %{stop_reason: "end_turn", content: content}} ->
        {{:ok, Mehungry.AI.Client.text_from(%{content: content}), acc}, iteration}

      {:ok, %{stop_reason: "tool_use", content: content}} ->
        Logger.debug("AI.Agent: iteration #{iteration} — executing tool calls")
        {tool_results, acc} = dispatch_tools(content, handler, acc, meta)

        new_messages =
          messages ++
            [%{role: "assistant", content: content}] ++
            [%{role: "user", content: tool_results}]

        loop(new_messages, handler, acc, req_base, iteration + 1, max_iter, meta)

      {:ok, %{stop_reason: "max_tokens"}} ->
        Logger.warning(
          "AI.Agent: stop_reason max_tokens — increase max_tokens or reduce prompt size"
        )

        {{:error, :max_tokens_reached}, iteration}

      {:ok, %{stop_reason: stop, content: content}} ->
        Logger.warning("AI.Agent: unexpected stop_reason #{inspect(stop)}")
        {{:ok, Mehungry.AI.Client.text_from(%{content: content}), acc}, iteration}

      {:error, reason} ->
        {{:error, reason}, iteration}
    end
  end

  # ── tool dispatch ─────────────────────────────────────────────────────────────

  # Folds the accumulator through each tool_use block left-to-right so multiple
  # tool calls in a single assistant turn each see the state the previous one left.
  # Each call is wrapped in a telemetry span tagged by tool name + agent.
  defp dispatch_tools(content_blocks, handler, acc, meta) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map_reduce(acc, fn %{"id" => id, "name" => name, "input" => input}, acc ->
      Logger.info("AI.Agent: tool #{name}(#{inspect(input)})")
      tool_meta = Map.put(meta, :tool, name)

      {result, acc} =
        :telemetry.span([:mehungry, :ai, :agent, :tool], tool_meta, fn ->
          {value, status} =
            try do
              {handler.(name, input, acc), "ok"}
            rescue
              e ->
                Logger.error("AI.Agent: tool #{name} raised: #{Exception.message(e)}")
                {{%{error: "Tool execution failed: #{Exception.message(e)}"}, acc}, "error"}
            end

          {value, Map.put(tool_meta, :status, status)}
        end)

      {%{type: "tool_result", tool_use_id: id, content: Jason.encode!(result)}, acc}
    end)
  end

  # ── helpers ───────────────────────────────────────────────────────────────────

  # The Messages-API client is resolved through config so tests can stub the
  # network with canned tool_use/end_turn responses (`:ai_client` key); defaults
  # to the real Mehungry.AI.Client.
  defp client, do: Application.get_env(:mehungry, :ai_client, Mehungry.AI.Client)

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
