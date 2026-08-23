# Mehungry Observability

> **Note (fresh start):** The previous bespoke DIY-observability system was removed
> in favour of a clean, standard baseline. This document describes what exists now.
> If you are looking for the old `MetricsBuffer` snapshot store, DIY `ErrorTracker`,
> query-time profiles, custom LiveDashboard pages, process watchdog, or the custom
> VM/pool gauges — **they no longer exist.** They were deleted (code, DB tables
> `telemetry_snapshots` / `error_events` / `query_time_profiles`, the
> `TelemetryPrunerWorker` cron, and the custom dashboard pages) so observability
> can be rebuilt intentionally from a standard foundation.

## What exists today

Observability is now **stock Phoenix telemetry + PromEx** — nothing DB-backed, no
in-app error tracker, no alerting.

There are two telemetry consumers, split by surface:

- **`MehungryWeb.PromEx`** owns the **Prometheus scrape path**. It's a `use PromEx`
  module started in the supervision tree (before the Endpoint) whose `plugins/0`
  registers the standard PromEx plugin set — `Beam`, `Application`, `Phoenix`
  (router + endpoint), `PhoenixLiveView`, `Ecto` (`Mehungry.Repo`), and `Oban`
  (default instance). PromEx attaches the telemetry handlers and aggregates into
  the Prometheus text format; the controller renders it via `PromEx.get_metrics/1`.
  Grafana dashboard upload and PromEx's standalone metrics HTTP server are disabled
  (`grafana: :disabled`, `metrics_server: :disabled` in `config.exs`) — we scrape
  through our own token-guarded endpoint. It's **enabled in test** so `GET /metrics`
  exercises its real output.

- **`MehungryWeb.Telemetry`** is now only the **LiveDashboard** metric source.
  `metrics/0` is the canonical list of standard metrics rendered as live charts;
  the supervisor also starts a `:telemetry_poller`. It no longer runs a Prometheus
  reporter (that moved to PromEx).

`MehungryWeb.Telemetry.metrics/0` (LiveDashboard charts):

- **Phoenix** — `phoenix.endpoint.stop.duration`, `phoenix.router_dispatch.stop.duration` (tagged by `route`)
- **Ecto** — `mehungry.repo.query.{total_time,query_time,queue_time}`
- **Oban** — `oban.job.stop.{duration,queue_time}` (tagged by `queue`, `worker`), `oban.job.exception.count`
- **VM** — `vm.memory.total`, `vm.total_run_queue_lengths.{total,cpu,io}` (emitted by the `telemetry_poller` application's own default poller)

### 2. Where metrics are viewed

| Surface | Route | Auth |
|---|---|---|
| **LiveDashboard** (live charts of `MehungryWeb.Telemetry.metrics/0`, ecto stats) | `/dashboard` | admin (`:admin_email` + `RequireAdmin`) |
| **Prometheus scrape** (PromEx output in text exposition format) | `GET /metrics` | token (`RequireMetricsToken` / `:metrics_api_token`) |
| **BeamScope** dashboard + its own scrape | `/beam_scope`, `GET /beam_scope/metrics` | admin (dashboard) / token (scrape) |
| **Oban Web** (job queues — view/retry/cancel) | `/oban` | admin |

`GET /metrics` is served by `MehungryWeb.MetricsController`, which calls
`PromEx.get_metrics(MehungryWeb.PromEx)` (returns `503` if PromEx is down). Metric
names are PromEx-prefixed (e.g. `mehungry_web_prom_ex_phoenix_http_requests_total`,
`…_ecto_…`, `…_oban_…`, `…_beam_…`).

`GET /beam_scope/metrics` renders `BeamScope.Exporter.Prometheus.scrape/0`, also via
`MehungryWeb.MetricsController` and token-guarded so a Prometheus job can reach it
without the session admin auth on the `/beam_scope` dashboard forward.

### AI agent & Anthropic API metrics

`Mehungry.AI.Agent` and `Mehungry.AI.Client` emit `:telemetry`, aggregated onto the
same scrape by the custom **`MehungryWeb.PromEx.AiPlugin`** (registered in
`MehungryWeb.PromEx.plugins/0`) and mirrored into LiveDashboard via
`MehungryWeb.Telemetry.metrics/0`. Every agent run is tagged by `agent`
(`recipe` / `meal_plan` / `nutritionist`) so metrics split per agent.

Raw events:

- `[:mehungry, :ai, :agent, :run, :start | :stop]` — `duration` + `iterations`
  measurements; `:stop` metadata `outcome` ∈ `end_turn` / `max_iterations` /
  `max_tokens` / `error` (the reliability signal).
- `[:mehungry, :ai, :agent, :tool, :start | :stop]` — per tool call, metadata
  `tool`, `agent`, `status` (`ok` / `error` when a handler raises).
- `[:mehungry, :ai, :agent, :no_submit_retry]` — RecipeAgent runs re-prompted
  because the model finished without calling `submit_recipe`.
- `[:mehungry, :ai, :client, :request, :stop]` — Anthropic API `duration` +
  `input_tokens` / `output_tokens`, metadata `model`, `status` (cost/latency).

Prometheus families (all `mehungry_web_prom_ex_ai_*`): `agent_run_total`,
`agent_run_duration_milliseconds`, `agent_run_iterations`,
`agent_no_submit_retry_total`, `agent_tool_total`,
`agent_tool_duration_milliseconds`, `client_request_total`,
`client_request_duration_milliseconds`, `client_{input,output}_tokens_total`.

**Grafana:** since PromEx's Grafana upload is disabled, import
`grafana/ai_agents_dashboard.json` manually (Dashboards → Import → upload JSON →
pick your Prometheus datasource). Panels cover run outcomes, non-success ratio,
no-submit retries, run duration/iteration percentiles (ceiling watch), tool
call/latency by tool, and token/latency by model. Token cost is attributed by
`model` only — the client layer doesn't know which agent called it; per-agent
token attribution would need the loop to thread `usage` back (future work).

### 3. What is deliberately absent

- No persistent metric history (LiveDashboard is live-only; scrape into an external
  Prometheus/Grafana if you need retention).
- No in-app error tracking (no Sentry either — errors surface in logs).
- No alerting.

These are intentional omissions for the fresh start — add them deliberately if/when
needed rather than resurrecting the removed DIY layer.
