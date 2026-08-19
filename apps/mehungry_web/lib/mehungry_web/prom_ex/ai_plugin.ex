defmodule MehungryWeb.PromEx.AiPlugin do
  @moduledoc """
  PromEx plugin for the AI agent subsystem.

  Turns the telemetry `Mehungry.AI.{Client, Agent}` emit into Prometheus metrics
  so agent reliability and cost are visible on the same scrape as the standard
  Phoenix/Ecto/Oban plugins. Registered in `MehungryWeb.PromEx.plugins/0`.

  Metric families (all `mehungry_web_prom_ex_ai_*`):

    * `agent_run_total` — runs by `agent` × `outcome`
      (`end_turn` / `max_iterations` / `max_tokens` / `error`). The core
      reliability signal — a rising `max_iterations`/`error` share means the loop
      is failing to converge.
    * `agent_run_duration_milliseconds` / `agent_run_iterations` — how long and
      how many tool-loop turns each run takes (are we brushing the ceiling?).
    * `agent_tool_total` / `agent_tool_duration_milliseconds` — tool calls by
      `tool` × `status`, catching tool handlers that raise or thrash.
    * `agent_no_submit_retry_total` — RecipeAgent runs that ended without calling
      submit and had to be re-prompted.
    * `client_request_*` — Anthropic API latency, count, and token usage by
      `model` (cost tracking).

  See `docs/infrastructure/observability.md` and `grafana/ai_agents_dashboard.json`.
  """

  use PromEx.Plugin

  @run_stop [:mehungry, :ai, :agent, :run, :stop]
  @tool_stop [:mehungry, :ai, :agent, :tool, :stop]
  @no_submit [:mehungry, :ai, :agent, :no_submit_retry]
  @client_stop [:mehungry, :ai, :client, :request, :stop]

  @duration_buckets [50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000, 60_000, 120_000]
  @iteration_buckets [1, 2, 3, 4, 5, 6, 8, 10, 12, 16]

  @impl true
  def event_metrics(_opts) do
    [
      agent_run_metrics(),
      agent_tool_metrics(),
      client_request_metrics()
    ]
  end

  defp agent_run_metrics do
    Event.build(:mehungry_ai_agent_run_event_metrics, [
      counter(
        [:mehungry_web, :prom_ex, :ai, :agent, :run, :total],
        event_name: @run_stop,
        description: "Total AI agent runs, tagged by agent and terminal outcome.",
        tags: [:agent, :outcome]
      ),
      distribution(
        [:mehungry_web, :prom_ex, :ai, :agent, :run, :duration, :milliseconds],
        event_name: @run_stop,
        measurement: :duration,
        description: "Wall-clock duration of an AI agent run.",
        reporter_options: [buckets: @duration_buckets],
        unit: {:native, :millisecond},
        tags: [:agent, :outcome]
      ),
      distribution(
        [:mehungry_web, :prom_ex, :ai, :agent, :run, :iterations],
        event_name: @run_stop,
        measurement: :iterations,
        description: "Number of tool-loop iterations an AI agent run took.",
        reporter_options: [buckets: @iteration_buckets],
        tags: [:agent, :outcome]
      ),
      counter(
        [:mehungry_web, :prom_ex, :ai, :agent, :no_submit_retry, :total],
        event_name: @no_submit,
        description: "Agent runs that ended without submitting and were re-prompted.",
        tags: [:agent]
      )
    ])
  end

  defp agent_tool_metrics do
    Event.build(:mehungry_ai_agent_tool_event_metrics, [
      counter(
        [:mehungry_web, :prom_ex, :ai, :agent, :tool, :total],
        event_name: @tool_stop,
        description: "Total tool calls, tagged by tool name and ok/error status.",
        tags: [:agent, :tool, :status]
      ),
      distribution(
        [:mehungry_web, :prom_ex, :ai, :agent, :tool, :duration, :milliseconds],
        event_name: @tool_stop,
        measurement: :duration,
        description: "Duration of a single tool handler call.",
        reporter_options: [buckets: @duration_buckets],
        unit: {:native, :millisecond},
        tags: [:agent, :tool, :status]
      )
    ])
  end

  defp client_request_metrics do
    Event.build(:mehungry_ai_client_request_event_metrics, [
      counter(
        [:mehungry_web, :prom_ex, :ai, :client, :request, :total],
        event_name: @client_stop,
        description: "Total Anthropic API requests, tagged by model and status.",
        tags: [:model, :status]
      ),
      distribution(
        [:mehungry_web, :prom_ex, :ai, :client, :request, :duration, :milliseconds],
        event_name: @client_stop,
        measurement: :duration,
        description: "Anthropic API request latency (including retries).",
        reporter_options: [buckets: @duration_buckets],
        unit: {:native, :millisecond},
        tags: [:model, :status]
      ),
      sum(
        [:mehungry_web, :prom_ex, :ai, :client, :input_tokens, :total],
        event_name: @client_stop,
        measurement: :input_tokens,
        description: "Cumulative input tokens sent to the Anthropic API, by model.",
        tags: [:model]
      ),
      sum(
        [:mehungry_web, :prom_ex, :ai, :client, :output_tokens, :total],
        event_name: @client_stop,
        measurement: :output_tokens,
        description: "Cumulative output tokens received from the Anthropic API, by model.",
        tags: [:model]
      )
    ])
  end
end
