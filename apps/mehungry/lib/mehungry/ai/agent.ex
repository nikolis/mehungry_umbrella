defmodule Mehungry.AI.Agent do
  @moduledoc """
  Generic tool-use loop for Anthropic-powered agents.

  Runs a conversation with the AI until `stop_reason` is `"end_turn"` or
  `max_iterations` is reached. On each `"tool_use"` stop it dispatches the
  requested tool calls to a caller-supplied handler function and appends the
  results as the next user turn, then continues the loop.

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
        "search_ingredient", %{"name" => name}, _ctx ->
          Mehungry.Food.IngredientSearch.search(name) |> Enum.take(5) |> Enum.map(& &1.name)
        _, _, _ ->
          %{error: "unknown tool"}
      end

      {:ok, text} = Mehungry.AI.Agent.run(system, user_msg, tool_defs, handler, %{})
  """

  require Logger

  @default_max_iterations 10

  @type tool_def :: %{
          name: String.t(),
          description: String.t(),
          input_schema: map()
        }

  @type tool_handler :: (String.t(), map(), any() -> any())

  @doc """
  Runs the agent loop.

  Arguments:
    - `system`       — system prompt string
    - `user_message` — initial user turn (string or list of content blocks)
    - `tool_defs`    — list of `%{name, description, input_schema}` tool maps
    - `handler`      — `fn(tool_name, tool_input, context) -> result`
                       result must be JSON-encodable
    - `context`      — arbitrary value passed through to `handler` unchanged
    - `opts`         — keyword list:
                         `:max_iterations` (default #{@default_max_iterations})
                         `:model`          (overrides client default)
                         `:max_tokens`     (overrides client default)

  Returns `{:ok, text}` or `{:error, reason}`.
  """
  @spec run(String.t(), any(), [tool_def()], tool_handler(), any(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def run(system, user_message, tool_defs, handler, context, opts \\ []) do
    request_base =
      %{system: system, tools: tool_defs}
      |> put_if_present(:model, Keyword.get(opts, :model))
      |> put_if_present(:max_tokens, Keyword.get(opts, :max_tokens))

    messages = [%{role: "user", content: user_message}]
    max_iter = Keyword.get(opts, :max_iterations, @default_max_iterations)

    loop(messages, handler, context, request_base, 0, max_iter)
  end

  # ── loop ─────────────────────────────────────────────────────────────────────

  defp loop(_messages, _handler, _ctx, _req, max, max) do
    Logger.warning("AI.Agent: reached max_iterations (#{max}), stopping")
    {:error, :max_iterations_reached}
  end

  defp loop(messages, handler, ctx, req_base, iteration, max_iter) do
    request = Map.put(req_base, :messages, messages)

    case Mehungry.AI.Client.request(request) do
      {:ok, %{stop_reason: "end_turn", content: content}} ->
        {:ok, Mehungry.AI.Client.text_from(%{content: content})}

      {:ok, %{stop_reason: "tool_use", content: content}} ->
        Logger.debug("AI.Agent: iteration #{iteration} — executing tool calls")
        tool_results = dispatch_tools(content, handler, ctx)

        new_messages =
          messages ++
            [%{role: "assistant", content: content}] ++
            [%{role: "user", content: tool_results}]

        loop(new_messages, handler, ctx, req_base, iteration + 1, max_iter)

      {:ok, %{stop_reason: "max_tokens"}} ->
        Logger.warning(
          "AI.Agent: stop_reason max_tokens — increase max_tokens or reduce prompt size"
        )

        {:error, :max_tokens_reached}

      {:ok, %{stop_reason: stop, content: content}} ->
        Logger.warning("AI.Agent: unexpected stop_reason #{inspect(stop)}")
        {:ok, Mehungry.AI.Client.text_from(%{content: content})}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── tool dispatch ─────────────────────────────────────────────────────────────

  defp dispatch_tools(content_blocks, handler, ctx) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn %{"id" => id, "name" => name, "input" => input} ->
      Logger.info("AI.Agent: tool #{name}(#{inspect(input)})")

      result =
        try do
          handler.(name, input, ctx)
        rescue
          e ->
            Logger.error("AI.Agent: tool #{name} raised: #{Exception.message(e)}")
            %{error: "Tool execution failed: #{Exception.message(e)}"}
        end

      %{
        type: "tool_result",
        tool_use_id: id,
        content: Jason.encode!(result)
      }
    end)
  end

  # ── helpers ───────────────────────────────────────────────────────────────────

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, key, value), do: Map.put(map, key, value)
end
