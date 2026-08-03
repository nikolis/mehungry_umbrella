# Mehungry Observability — Operator's Manual

This document explains the full observability system: what exists, how to use it,
what every value means, which problems it can diagnose (and how), where it falls
short, and what to build next.

Last updated: 2026-07-05 — `Mehungry.Telemetry.MetricsBuffer` now persists most of
what used to be live-only: `repo.query.total_time`/`queue_time`, `oban.job.duration`/
`.queue_time`/`.exception.count`, `cache.size`, `oban.queue.depth`,
`vm.process.max_message_queue`/`.over_threshold_count`, `vm.scheduler.utilization`/
`.weighted`, and `vm.memory.total` all now flow into `telemetry_snapshots`
alongside the original three. Two brand-new gauges were added:
`mehungry.vm.live_view.count` (concurrent LiveView connections, §3.10) and
`mehungry.repo.pool.busy`/`.total`/`.pool_size` (DB pool utilization, §3.11). Also
fixed a pre-existing bug where the live `oban.job.stop.*`/`oban.job.exception.count`
Metrics-tab entries were extracting tags from the wrong metadata shape and almost
certainly rendering blank. `phoenix.request.count`, `phoenix.endpoint.duration`,
and `vm.total_run_queue_lengths.*` remain live-only — deferred, not forgotten;
see §9.

**Prior correction (same day, still relevant context):** an earlier draft of this
doc claimed all of the above were already persisted "just missing a dashboard
page." That was wrong at the time — `MetricsBuffer` only had handlers for 4
telemetry events. This pass is the actual fix for that gap, not just a doc
correction.

---

## 1. Architecture overview

Every signal starts as a `:telemetry` event and fans out to up to three independent
consumers. Detaching or crashing one consumer never affects the others.

```
                    ┌────────────────────────────────────────────────────────┐
                    │                   :telemetry events                    │
                    │ [:mehungry,:repo,:query]        [:oban,:job,*]         │
                    │ [:phoenix,:router_dispatch,*]   [:phoenix,:endpoint,*] │
                    │ [:phoenix,:live_view,*,*]                              │
                    │ [:mehungry,:cache] [:mehungry,:oban,:queue]            │
                    │ [:mehungry,:vm,:process] [:mehungry,:vm,:scheduler]    │
                    │ [:mehungry,:vm,:live_view] [:mehungry,:repo,:pool]     │
                    │ [:vm,:memory] [:vm,:total_run_queue_lengths]           │
                    └──────┬───────────────┬───────────────┬─────────────────┘
                           │               │               │
              ┌────────────┘               │               └────────────┐
              ▼                            ▼                            ▼
   LIVE METRICS (ephemeral)      PERSISTENT METRICS (MetricsBuffer)   ERROR TRACKER
   MehungryWeb.Telemetry         13 telemetry events attached,        GenServer.cast
   (telemetry_metrics defs —     3 ETS tables, flush 5 min            → upsert
   ALL of the events above           │         │         │                │
   feed live charts here)            ▼         ▼         ▼                ▼
              │               telemetry_  query_   query_timeline   error_events
              ▼               snapshots   time_    (in-memory only, table (30d)
   /dashboard → Metrics tab   (30d, ~13   profiles  60 min, trimmed      │
   (gone when you close it)   metric      (30d)     every flush)        ▼
   Also emits [ProcessWatchdog]  families,   │           │        /dashboard →
   warning logs from its 10s     see §3)     │           │         Errors tab
   poller (see §5)                  │        ▼           ▼
                                    ▼    /dashboard → /dashboard →
                              /dashboard →  Queries   Query Timeline
                              Endpoints tab  tab       tab
```

Poller-driven sources feed the event stream every **10 seconds**
(`MehungryWeb.Telemetry.periodic_measurements/0`): Cachex sizes, Oban queue
depths, process mailbox stats + LiveView connection count, scheduler
utilization, and DB pool stats. All of them feed the live Metrics tab; **most of
them now also reach `MetricsBuffer`** (see below) — a change from earlier in the
day.

**What `MetricsBuffer` persists today.** It attaches to 13 telemetry events. All
but one produce a generic `telemetry_snapshots` row via the shared `record/3` →
`flush/0` pipeline (aggregated per `{metric, tags}` every 5 minutes):

| Event | Metric(s) persisted | Tags |
|---|---|---|
| `[:phoenix, :router_dispatch, :stop]` | `phoenix.request.duration` | `route` |
| `[:phoenix, :live_view, :mount, :stop]` | `live_view.mount.duration` | `view` |
| `[:phoenix, :live_view, :handle_event, :stop]` | `live_view.handle_event.duration` | `view`, `event` |
| `[:oban, :job, :stop]` | `oban.job.duration`, `oban.job.queue_time` | `queue`, `worker` |
| `[:oban, :job, :exception]` | `oban.job.exception.count` | `queue`, `worker` |
| `[:mehungry, :cache]` | `mehungry.cache.size` | `cache` |
| `[:mehungry, :oban, :queue]` | `mehungry.oban.queue.depth` | `queue` |
| `[:mehungry, :vm, :process]` | `mehungry.vm.process.max_message_queue`, `.over_threshold_count` | — |
| `[:mehungry, :vm, :scheduler]` | `mehungry.vm.scheduler.utilization`, `.weighted` | — |
| `[:vm, :memory]` | `vm.memory.total` (KB) | — |
| `[:mehungry, :vm, :live_view]` | `mehungry.vm.live_view.count` | — |
| `[:mehungry, :repo, :pool]` | `mehungry.repo.pool.busy`, `.total`, `.pool_size` | — |

The 13th event, `[:mehungry, :repo, :query]`, is the exception: it does **not**
write a generic snapshot row via `record/3` for `total_time`/`queue_time`
(handled by tagging above), but its `query_time` measurement goes through two
*other* dedicated pipelines instead of the generic one: fingerprinted by
`{source, SQL text}` and flushed to `query_time_profiles` every 5 min (§3.8), and
recorded raw (one row per execution, tagged with the triggering action via
`ActionContext`) in an in-memory-only ETS table, the Query Timeline (§3.9).

**Still live-only — deferred, see §9:** `phoenix.request.count`,
`phoenix.endpoint.duration`, and `vm.total_run_queue_lengths.total`/`.cpu`/`.io`.
These are the only entries in `MehungryWeb.Telemetry.metrics/0` without a
`MetricsBuffer` handler today.

### Module inventory

| Module | File | Role |
|---|---|---|
| `MehungryWeb.Telemetry` | `apps/mehungry_web/lib/mehungry_web/telemetry.ex` | Live metric definitions for the dashboard Metrics tab; 10s poller (cache sizes, queue depths, process watchdog + LiveView count, scheduler utilization, DB pool stats) |
| `Mehungry.Telemetry.ActionContext` | `apps/mehungry/lib/mehungry/telemetry/action_context.ex` | Tags the current process (via the process dictionary) with a label describing the HTTP request / LiveView callback / Oban job it's currently running, by attaching to Phoenix/LiveView/Oban `:start`/`:stop`/`:exception` spans. `MetricsBuffer` reads it synchronously at query time to attribute each query to the action that fired it. Not propagated across `Task.async` — queries fired from a spawned Task show up as `"background"` |
| `Mehungry.Telemetry.MetricsBuffer` | `apps/mehungry/lib/mehungry/telemetry/metrics_buffer.ex` | Attaches to 13 telemetry events (table above). Buffers raw samples in three ETS tables and, every 5 min, aggregates (min/avg/max/p95/count) into `telemetry_snapshots` and `query_time_profiles` (per query-fingerprint); also maintains the in-memory-only, 60-minute Query Timeline exposed via `list_recent_query_events/1` |
| `Mehungry.Telemetry.Snapshot` | `apps/mehungry/lib/mehungry/telemetry/snapshot.ex` | Ecto schema for `telemetry_snapshots` |
| `Mehungry.Telemetry.QueryProfile` | `apps/mehungry/lib/mehungry/telemetry/query_profile.ex` | Ecto schema for `query_time_profiles` — per-query-shape timing history |
| `Mehungry.Telemetry.ErrorTracker` | `apps/mehungry/lib/mehungry/telemetry/error_tracker.ex` | Catches Phoenix/LiveView/Oban exceptions, fingerprints, dedup-upserts into `error_events` |
| `Mehungry.Telemetry.ErrorEvent` | `apps/mehungry/lib/mehungry/telemetry/error_event.ex` | Ecto schema for `error_events` |
| `Mehungry.SqlUtils` | `apps/mehungry/lib/mehungry/sql_utils.ex` | `iex` helper: `explain_analyze/3` runs `EXPLAIN (ANALYZE, BUFFERS)` on a raw SQL string (e.g. copied out of the Queries or Query Timeline tab) without hand-editing it into a query. `format: :map` returns the parsed JSON plan instead of printing it |
| `Mehungry.ObanWorkers.TelemetryPrunerWorker` | `apps/mehungry/lib/mehungry/oban_workers/telemetry_pruner_worker.ex` | Cron (03:00 UTC daily): deletes snapshots, error events, and query profiles older than **30 days** |
| `MehungryWeb.ErrorsPage` | `apps/mehungry_web/lib/mehungry_web/live/errors_page.ex` | Dashboard page over `error_events` |
| `MehungryWeb.QueryTimesPage` | `apps/mehungry_web/lib/mehungry_web/live/query_times_page.ex` | Dashboard page over `query_time_profiles` — one row per distinct query shape, worst p95 first, click to expand full SQL |
| `MehungryWeb.EndpointTimesPage` | `apps/mehungry_web/lib/mehungry_web/live/endpoint_times_page.ex` | Dashboard page over `telemetry_snapshots`, filtered to `phoenix.request.duration` / `live_view.mount.duration` / `live_view.handle_event.duration` — the persisted-history equivalent of the live Metrics tab, scoped to HTTP/LiveView latency. **Not** updated to show the newly-persisted metrics (§7) |
| `MehungryWeb.QueryTimelinePage` | `apps/mehungry_web/lib/mehungry_web/live/query_timeline_page.ex` | Dashboard page over the in-memory Query Timeline — raw query executions from the last 5/15/30/60 min, grouped by the action that fired them; expand a group to see every query, expand a row for the full SQL |
| `MehungryWeb.Plugs.RequireAdmin` | `apps/mehungry_web/lib/mehungry_web/plugs/require_admin.ex` | Gates `/dashboard`; 404 for non-admins |

Attachment points: `ActionContext.attach()` runs first thing in
`Mehungry.Application.start/2` (a plain `:telemetry.attach`, not a supervised
process — it has to be in place before any request/job runs so query attribution
works from the start). `MetricsBuffer` and `ErrorTracker` attach their own
handlers in their own `init/1` as supervised `GenServer`s. All handlers tolerate
`{:error, :already_exists}` so restarts are safe.

**Removed earlier the same day:** `Mehungry.Telemetry.SlowQueryLogger` and
`Mehungry.Telemetry.SlowRequestLogger` (the modules that used to log `[SlowQuery]`
≥500ms / `[SlowRequest]` ≥2s warnings). Slow-op discovery now happens by opening
the Queries / Endpoints / Query Timeline dashboard pages, or querying
`telemetry_snapshots` directly, rather than grepping logs — see §5 and §8.

---

## 2. Access & the dashboard tabs

**URL:** `https://<host>/dashboard`

**Auth:** the scope pipes through `:admin_browser → :require_authenticated_user →
:require_admin`. `RequireAdmin` compares `current_user.email` against
`config :mehungry, :admin_email` (set in `config/config.exs`) and responds **404**
(not 403) to anyone else, so the route's existence is not advertised. The same
config key drives `AdminAuthLive` for the `/professional` LiveViews.

| Tab | What it's for |
|---|---|
| **Home** | BEAM basics: uptime, total memory, atom/port/process counts |
| **Metrics** | Live charts of everything in `MehungryWeb.Telemetry.metrics/0`. Real-time only — data starts when you open the page and dies when you close it |
| **Request Logger** | Stream logs for a single request via a signed param/cookie. Use to debug one misbehaving request interactively |
| **Processes / Ports / Sockets / ETS** | Live process table. Sort by *Message queue* to find stuck processes, by *Memory* or *Reductions* for hogs. This is the manual companion to the automated watchdog |
| **Ecto Stats** | `ecto_psql_extras` panels against the RDS instance: index usage & cache hit rates, seq scans, unused indexes, locks, long-running transactions, table bloat. `outliers`/`calls` panels need `pg_stat_statements` enabled on RDS (parameter group change) |
| **Errors** | Grouped errors from `error_events`, newest first (last 100 fingerprints). Click a row to expand full reason, stacktrace and context |
| **Queries** | Per-query `query_time` history from `query_time_profiles`, one row per distinct query shape (`source` + SQL text), worst p95 first over the selected range (1h/6h/24h/7d). Click a row to expand the full SQL text |
| **Endpoints** | Persisted p95 history for `phoenix.request.duration`, `live_view.mount.duration` and `live_view.handle_event.duration` from `telemetry_snapshots`, worst p95 first over the selected range |
| **Query Timeline** | Raw, unaggregated query executions from the last 5/15/30/60 minutes, grouped by the HTTP request / LiveView callback / Oban job that fired them. In-memory only, not written to Postgres. The tool for spotting N+1s: one group with many small queries and a high total is the tell |
| **LocalAI Rate** | Requests/min for the token-guarded LocalAi REST API (`/api/local_ai/*`), per route and overall, over the selected range (1h/6h/24h/7d). Computed by `Mehungry.Telemetry.RequestRate.local_ai/1` from the `phoenix.request.duration` snapshots (`sample_count / window`); a banner adds the live count from the in-memory buffer since the last flush. Also exposed as curl-able JSON at `GET /api/local_ai/metrics?window_seconds=` (same shared-secret token as the rest of that API) |

Note: `mehungry.cache.size`, `oban.job.duration`/`.queue_time`/`.exception.count`,
`mehungry.oban.queue.depth`, `mehungry.vm.process.*`, `mehungry.vm.scheduler.*`,
`vm.memory.total`, `mehungry.vm.live_view.count`, and `mehungry.repo.pool.*` are
now all durably persisted to `telemetry_snapshots` — but **no dashboard page
reads any of them back yet**. The Endpoints/Queries tabs are still scoped to the
original three HTTP/LiveView metrics and the query-fingerprint table
respectively. Until a page is built for the rest (§9), you query
`telemetry_snapshots` directly for their history — see §7 for exactly how.
`phoenix.request.count` and `phoenix.endpoint.duration` remain genuinely
live-only (§1, §9) — no historical record exists for those two, dashboard page
or otherwise.

---

## 3. Metric reference

### 3.1 How to read a snapshot row

Every row in `telemetry_snapshots` (whether from the Endpoints/Queries pages or a
manual query) is a **5-minute aggregation window** for one `{metric, tags}` pair:

| Column | Meaning |
|---|---|
| **Avg** | Arithmetic mean of all samples in the window. Good for trends, hides outliers |
| **Min / Max** | Extremes in the window. A huge Max with a normal Avg = a single outlier |
| **p95** | 95% of samples were at or below this. **The number to watch for latency**: users experience the tail, not the average. p95 ≫ avg means inconsistent performance (lock contention, cold caches, GC pauses, one bad query variant) |
| **# Samples** | How many events landed in the window. Doubles as a rate: `samples / 300` = events per second. A duration metric with samples collapsing toward zero can mean traffic dropped *or* the emitter broke — cross-check another metric |

Caveat: p95 is computed per window (`ceil(0.95 × n) - 1` on the sorted values) and
**cannot be averaged across windows**. The Endpoints/Queries pages handle this
correctly by keeping each row's *worst* window's p95 within the selected range,
rather than averaging; if you query `telemetry_snapshots` by hand, do the same.

For counter-style metrics, every sample has value 1.0, so min/avg/max/p95 are all
1.0 and **# Samples is the count**. `oban.job.exception.count` is exactly this
shape today — a genuine, persisted counter. `phoenix.request.count` would look
identical if/when it's added (§9); it isn't persisted yet.

### 3.2 Database

| Metric | Tags | Unit | Meaning |
|---|---|---|---|
| `mehungry.repo.query.total_time` | `source` (table name) | ms | Full query lifetime: pool queue + execution + decode. Tagged by the Ecto source table, so you can see *which table's* queries degraded. **Persisted** — query `telemetry_snapshots` directly (§7); no dedicated dashboard page yet |
| `mehungry.repo.query.queue_time` | `source` | ms | Time spent waiting for a connection from the pool. **Only recorded when > 0**. **Persisted** — same caveats as `total_time` |
| `mehungry.repo.query.query_time` | — (live Metrics tab; also feeds §3.8/§3.9) | ms | Raw DB execution time, untagged as a live metric. Historical coverage comes through a different path: **use the Queries tab** for the per-statement aggregate, or the **Query Timeline tab** for raw per-execution history tied to the action that ran it |

**What healthy looks like:** `total_time` p95 in single-digit ms for indexed lookups,
tens of ms for search/aggregations. `queue_time` mostly absent or < 1 ms.

**Interpreting divergence — this distinction matters more than any absolute number:**
- `queue_time` rising while per-query `total_time` is flat → **pool exhaustion**: too
  few connections, or something is holding connections (long transactions — check
  Ecto Stats → Locks / Long running queries, or the pool gauge in §3.11). All
  queries suffer at once. Both metrics now have real history — pull a 24h/7d
  trend from `telemetry_snapshots` (§7) instead of only catching it live.
- `total_time` rising for one `source` only → that table's queries got slow: missing
  index, table growth, plan change. Check Ecto Stats → Seq scans, and the
  Queries tab for the exact SQL (via `query_time`, which is persisted separately),
  then `Mehungry.SqlUtils.explain_analyze/3` in `iex` to `EXPLAIN ANALYZE` it
  directly.

### 3.3 HTTP requests

| Metric | Tags | Unit | Meaning |
|---|---|---|---|
| `phoenix.endpoint.duration` | — | ms | **Live-only, not persisted.** Whole-request time from `Plug.Telemetry` (`event_prefix: [:phoenix, :endpoint]`), covering every plug in the endpoint pipeline — session fetch, CSRF, everything — before and including router dispatch. Useful for telling "the router/controller is slow" apart from "something earlier in the plug pipeline is slow" |
| `phoenix.request.duration` | `route` (pattern, e.g. `/recipes/:id`) | ms | Router-dispatch duration per route pattern. Covers controllers and the *initial* (disconnected) LiveView render. Persisted — see the Endpoints tab |
| `phoenix.request.count` | `status` (`2xx`/`3xx`/`4xx`/`5xx`) | count | Response status class. **Error rate** = `5xx samples ÷ total samples` across the window. **Live-only** — the one HTTP metric still without a `MetricsBuffer` handler (deferred, §9); no historical 5xx-rate trend exists yet. The Errors tab is the durable record of individual failures, just not the *rate* |

**What healthy looks like:** near-zero `5xx`. A baseline of `4xx` is normal (bots,
expired sessions). `5xx` appearing at all → go straight to the Errors tab.

### 3.4 LiveView — the most important latency metrics in this app

Almost all authenticated UI is LiveView, and after the first page load navigation
happens over the websocket where **no HTTP request exists**. `phoenix.request.*`
sees none of it; these do:

| Metric | Tags | Unit | Meaning |
|---|---|---|---|
| `live_view.mount.duration` | `view` (last module segment, e.g. `CalendarLive.Index` → `Index`) | ms | Time in `mount/3`. This is the "page load feels slow" metric. Persisted — see the Endpoints tab |
| `live_view.handle_event.duration` | `view`, `event` | ms | Time handling one user interaction (button click, form change). This is the "UI feels laggy" metric. Persisted — see the Endpoints tab |

Caveats:
- **Mount fires twice per page load** — once for the disconnected HTTP render, once
  when the websocket connects. Sample counts are ~2× page views; both samples are
  real work the server did.
- The `view` tag is the *last* segment of the module (`Module.split |> List.last`),
  so `CalendarLive.Index` and `PostLive.Index` both show as `Index` — on the
  Endpoints tab and in the Query Timeline's action labels alike. Use the `event`
  tag and correlation with routes to disambiguate, or see §9 for the fix.
- A slow `handle_event` **blocks that user's entire LiveView process** — everything
  they do queues behind it. Anything with p95 > ~200 ms here is felt directly by
  the user. There's no threshold log for this (§5/§8) — the Endpoints tab
  (aggregate) and Query Timeline tab (what queries ran during it) are how you
  notice.
- `handle_params` duration is *not* measured as a metric (only its exceptions are
  caught, §4) — but queries fired during `handle_params` are correctly labeled in
  the Query Timeline via `ActionContext`, so you can still see what a slow
  `handle_params` did query-wise even without a duration number for it.
- For the "how many concurrent LiveView sessions are open" question, see
  `mehungry.vm.live_view.count` (§3.10) rather than trying to derive it from
  these two metrics' sample counts.

### 3.5 Background jobs (Oban)

| Metric | Tags | Unit | Meaning |
|---|---|---|---|
| `oban.job.duration` | `queue`, `worker` | ms | Job execution time per worker. **Persisted** — query `telemetry_snapshots` (§7); no dedicated dashboard page yet |
| `oban.job.queue_time` | `queue`, `worker` | ms | Time the job spent waiting to be picked up before execution started. **Persisted**, new metric (not previously tracked in any form, live or otherwise) |
| `oban.job.exception.count` | `queue`, `worker` | count (# Samples) | Failed executions — a genuine persisted counter (§3.1). Each occurrence also becomes a durable, fingerprinted row on the Errors tab with a stacktrace |
| `mehungry.oban.queue.depth` | `queue` | jobs | `available` (waiting, unclaimed) jobs, polled every 10 s. **Persisted** — but only a row exists for windows where a queue actually had `available` jobs; a queue at 0 depth the whole window produces no sample at all (not a 0-valued sample), because `emit_oban_queue_depths/0` only emits for queues it finds in the `available` state |

Queue concurrency (from `config/config.exs`): `default: 10`, `mailers: 5`,
`ai_agents: 2`.

**Interpreting depth:** transient spikes are fine. *Sustained growth* means intake >
throughput. On `ai_agents` (concurrency 2, AI calls taking 30–180 s each) a nightly
spike around 02:00 UTC is expected — `DailyRecipeGenerationWorker` fans out
generation jobs. Depth that hasn't drained by morning means jobs are failing and
retrying (check `oban.job.exception.count` + Errors tab) or an AI call pattern got
slower (check `oban.job.duration` p95 for the worker via a direct query, §7) — and
now you can pull a multi-day trend for both instead of only catching it live.

Note: exceptions count *executions*, and Oban retries (`max_attempts` varies by
worker) — one broken job can produce several exception samples. The Errors tab
`count` on the fingerprint tells you total occurrences; `context.attempt` shows how
deep into retries it got.

**Bug fixed this pass:** the live Metrics-tab entries for `oban.job.stop.duration`,
`oban.job.stop.queue_time`, and `oban.job.exception.count` in
`MehungryWeb.Telemetry.metrics/0` declared `tags: [:queue, :worker]` without a
`tag_values` function. Oban's telemetry metadata nests those fields under
`metadata.job` (`job.queue`/`job.worker`), not top-level, so `Telemetry.Metrics`'
default tag extraction (`Map.take(metadata, tags)`) was reading nothing — these
three live charts were almost certainly rendering with blank/missing tags before
this fix. Now fixed via a shared `oban_job_tags/1` helper (mirrored in
`MetricsBuffer` as `oban_job_tags/1` for the persisted versions, which never had
this bug since they always went through `metadata[:job]` explicitly).

### 3.6 Caches

| Metric | Tags | Unit | Meaning |
|---|---|---|---|
| `mehungry.cache.size` | `cache` | entries | Cachex entry count, polled every 10 s. **Persisted** — a slow staircase over days is now visible via a direct `telemetry_snapshots` query (§7), not just by opening the dashboard periodically and comparing by eye |

Configured limits: `recipes_cache` LRU **150**, `geo_cache` LRU **5000**,
`cache_user_tokens` unbounded.

- `recipes_cache` pegged at ~150 constantly = working set larger than the cache;
  recipes are being evicted and re-fetched (you'll also see "Getting recipe N from
  Database" log lines). Consider raising the limit.
- `cache_user_tokens` growing without bound = memory leak by design — worth watching
  alongside `vm.memory.total` (§3.7), now also persisted.
- A cache flat at 0 after deploy = it isn't being populated (broken invalidation or
  startup issue).

### 3.7 VM / runtime health

| Metric | Tags | Unit | Sampled | Meaning |
|---|---|---|---|---|
| `vm.memory.total` | — | byte in `:erlang.memory()`, stored in **KB** | telemetry_poller's default global poller | Total BEAM memory. Slow monotonic growth across days = leak (ETS, process state, binaries). Sawtooth is normal (GC). **Persisted** |
| `vm.total_run_queue_lengths.total`/`.cpu`/`.io` | — | count | telemetry_poller's default global poller | Runnable processes waiting for a scheduler. Near 0 when healthy. Sustained values above ~2× core count = CPU saturation. **Still live-only** (deferred, §9) — the one VM metric not yet persisted |
| `mehungry.vm.process.max_message_queue` | — | msgs | every 10 s (our poller, `emit_process_stats`) | Largest process mailbox in the system. Near 0 normally. Growth = some process can't keep up with its inbox (see the watchdog log for *which one*). **Persisted** |
| `mehungry.vm.process.over_threshold_count` | — | count | every 10 s | How many processes are over the 1000-message watchdog threshold right now. **Persisted** |
| `mehungry.vm.scheduler.utilization` | — | % (0–100) | every 10 s (our poller, `emit_scheduler_utilization`) | True scheduler busy time over the last ~10 s window, from `:scheduler.utilization/2` (scheduler wall time). Unlike OS CPU%, this excludes schedulers *spinning* while idle, so it's the honest "how busy is the BEAM" number. Sustained > ~80% = capacity ceiling: latency will rise before errors do. **Persisted** |
| `mehungry.vm.scheduler.weighted` | — | % | every 10 s (our poller) | Same, weighted against *total* capacity including dirty CPU/IO schedulers. Can legitimately exceed 100% under heavy dirty-scheduler load (NIFs, file IO). Diverging sharply from `utilization` = the work is happening on dirty schedulers (e.g. image processing via vix). **Persisted** |

Note `vm.memory.total` and `vm.total_run_queue_lengths.*` come from
`:telemetry_poller`'s own default global instance (started automatically by the
dependency, separate from `MehungryWeb.Telemetry`'s own 10s poller) — that's why
their exact sampling cadence isn't one of our knobs. The first `MetricsBuffer`
flush after a fresh boot/deploy may show a near-empty window for
`mehungry.vm.scheduler.*` specifically — `emit_scheduler_utilization/0` stores a
baseline on its first poller tick and only emits starting from the second.

### 3.8 Per-query time profiles (`query_time_profiles`)

`total_time` (§3.2) is tagged only by `source` table — useful for "which table
degraded" but not "which query". This table answers the latter: every
`[:mehungry,:repo,:query]` event's `query_time` (raw DB execution time, excluding
pool queue and decode) is fingerprinted by `sha256(source | SQL text)` — same
technique as the error tracker's fingerprinting — and aggregated every 5 min per
fingerprint, same min/avg/max/p95/sample_count shape as `telemetry_snapshots`.

**Dashboard:** the **Queries** tab, sorted worst-p95-first, one row per distinct
query shape. Click a row to expand the full SQL text (Ecto's parameterized form,
`$1`/`$2` placeholders — no literal values, so it's stable across executions with
different arguments and doesn't leak parameter data). Copy it straight into
`Mehungry.SqlUtils.explain_analyze/3` in `iex` to get a real `EXPLAIN ANALYZE`.

**Why a separate table instead of tagging `telemetry_snapshots`:** raw SQL text as
a tag would blow up that table's cardinality (§7 growth estimate). Keeping it in
its own table with its own page means the general metrics table's growth stays
predictable while still giving per-query visibility.

**Caveats:**
- Query text is truncated to 1000 chars before fingerprinting/storage
  (`@query_text_limit` in `MetricsBuffer`) — pathological giant `IN (...)` lists
  will collide if they diverge only past that point.
- Ecto's query text already omits literal values (they're bind parameters), so
  this is safe to browse without worrying about PII.
- Same 5-minute-loss-on-crash caveat as `telemetry_snapshots` (§8.1): an unclean
  stop loses the current window's in-flight ETS samples.
- A query with unstable shape (dynamically built via string interpolation rather
  than Ecto's query DSL) won't fingerprint consistently — this app's Ecto usage is
  all DSL-based, so this shouldn't come up, but worth knowing if that changes.

### 3.9 Query Timeline (in-memory, action-correlated)

Separate from both `telemetry_snapshots` and `query_time_profiles`, `MetricsBuffer`
also keeps every query execution **raw and unaggregated** in a third ETS table
(`ordered_set`, keyed by a monotonic integer), tagged with:

- `time` — when it ran
- `action` / `action_id` — the human label and unique id of whatever was running
  at the time (`"CalendarLive.Index#handle_event#save"`, `"HTTP GET /recipes/:id"`,
  `"Oban RecipeAgent"`, or `"background"` for anything fired from a spawned Task),
  supplied by `Mehungry.Telemetry.ActionContext`
- `source`, `query` (truncated to 1000 chars, same limit as §3.8), `duration_ms`

This is **never written to Postgres**. It's trimmed to the last 60 minutes on
every 5-minute flush tick, and read via
`Mehungry.Telemetry.MetricsBuffer.list_recent_query_events/1`.

**Dashboard:** the **Query Timeline** tab, range-filterable (5m/15m/30m/60m),
grouped by `action_id` — one collapsible group per request/callback/job, showing
query count and total time; expand a group to see every query, expand a query to
see its full SQL. This is the tool for spotting N+1s: a group with a high query
count and a low per-query duration but a high *total* is the classic pattern.

**Caveats:**
- 60-minute window, single node, gone on restart — it's a debugging aid for
  "what's happening right now / in the last hour", not a historical record.
- `ActionContext` doesn't propagate across `Task.async`/`Task.Supervisor` — queries
  fired from a spawned Task (including `Meta.enrich_visit_country`, which runs
  under `Mehungry.TaskSupervisor`) show up grouped under `"background"` rather than
  the request that spawned the Task.
- Queries fired outside any tracked span (e.g. from an `iex` session, or a
  `handle_info` callback — `ActionContext` doesn't attach to `handle_info`) also
  land in `"background"`.

### 3.10 Concurrent LiveView connections (`mehungry.vm.live_view.count`)

New this pass. Since the app is almost entirely LiveView, "how many people are
actively connected right now" is the closest thing to a users-per-node gauge —
and nothing measured it before.

**How it works:** `MehungryWeb.Telemetry.emit_process_stats/0` (already walking
every process every 10s for the mailbox watchdog) additionally calls
`:proc_lib.translate_initial_call(pid)` per process and counts how many resolve
to `{_mod, :mount, 3}` — the initial call every LiveView channel process sets on
itself. This piggybacks on a scan the poller was already paying for, so it's
effectively free. The count is emitted as its own event,
`[:mehungry, :vm, :live_view]`, and persisted untagged as
`mehungry.vm.live_view.count`.

**Caveats:**
- `Process.info(pid, :initial_call)` would be **useless** for this (always
  returns the generic `{:proc_lib, :init_p, 5}` for every OTP process) —
  `:proc_lib.translate_initial_call/1` is required.
- The discriminator is `:mount, 3` specifically, not "any long-lived socket
  process" — this app currently has zero real `Phoenix.Channel` implementations
  wired up (the `/socket` endpoint mount is dormant), so today every
  `:mount, 3`-tagged process is unambiguously a LiveView, but the check stays
  correct if channels are added later (they'd tag `:join, 3` instead).
- It's a poll-based gauge (accurate at each 10s sample), not an event-counted
  running total — deliberately, since Phoenix/LiveView fire a
  `[:phoenix, :socket_connected]` telemetry event on connect but **no
  corresponding event on disconnect/terminate**, so a connect-only counter could
  only ever grow.
- "Memory per connection" (total mem ÷ connection count) is not stored as its
  own metric — now that both `vm.memory.total` and this count are persisted
  independently, that ratio is derivable at analysis time from the two series
  without duplicating storage.

### 3.11 DB connection pool utilization (`mehungry.repo.pool.*`)

New this pass. `pool_size` (10 in dev, `POOL_SIZE` env var defaulting to 10 in
prod) is a static config value with no visibility into how close the pool is to
being exhausted, until now.

**How it works:** a new poller function, `MehungryWeb.Telemetry.emit_pool_stats/0`,
runs every 10s and queries Postgres's own `pg_stat_activity` — the same technique
the already-installed `ecto_psql_extras` dependency uses internally for its own
Connections/Locks LiveDashboard pages:

```sql
SELECT count(*) FILTER (WHERE state = 'active') AS busy, count(*) AS total
FROM pg_stat_activity WHERE datname = current_database()
```

Emits `[:mehungry, :repo, :pool]` with `busy`, `total`, and `pool_size`
(read live from `Mehungry.Repo.config()[:pool_size]`, not hardcoded). All three
are persisted untagged as `mehungry.repo.pool.busy`, `.total`, `.pool_size`.

**Assumption baked into this metric's meaning:** it counts **all** connections to
the database, not literally this app's Ecto pool checkouts — `DBConnection`
doesn't expose a clean public API for a true per-connection busy count without
reaching into the pool's internal pid (rejected as fiddlier than this approach).
This is only an accurate proxy for "this app's pool usage" if the database is
single-tenant for this app — **confirmed true** for this deployment (no other
services/consoles share the RDS database), so `total` ≈ this app's connection
count and `busy`/`pool_size` is a meaningful utilization ratio. If that ever
changes (another service, a shared PgBouncer, ad-hoc `psql` sessions during an
incident), this metric would overcount and should be filtered further (e.g. by
`application_name`, which Postgrex doesn't currently set to anything
distinguishing).

Uses non-bang `Ecto.Adapters.SQL.query/3` deliberately (not `query!/3`) — this
runs unattended in the poller every 10s; a transient DB hiccup skips a sample
rather than crashing the poller.

---

## 4. Error tracker reference

### What gets captured

| Source | Telemetry event | Context recorded |
|---|---|---|
| `plug` | `[:phoenix, :router_dispatch, :exception]` | `route` |
| `live_view` | `[:phoenix, :live_view, {mount \| handle_params \| handle_event}, :exception]` | `view`, `stage`, `event` (for handle_event) |
| `oban` | `[:oban, :job, :exception]` | `worker`, `queue`, `attempt` |

### How grouping (fingerprinting) works

Fingerprint = first 32 hex chars of
`sha256(source | kind | error type | first Mehungry-owned stack frame)` where *error
type* is the exception module (e.g. `Ecto.NoResultsError`) for exception structs, or
a truncated `inspect` for exits/throws.

**Deliberately excluded: the error message.** Messages embed ids, params and user
data (`could not find recipe 4182`), which would explode one bug into thousands of
"distinct" errors. Consequences to be aware of:

- Same exception module raised from the same app function with different messages →
  **one row**, `count` incremented. This is what you want 99% of the time.
- Two genuinely different bugs that raise the same exception type from the same
  function → merged into one row. The stored `reason`/`stacktrace` are from the
  *latest* occurrence.
- The same bug surfacing through both a controller and a LiveView → **two rows**
  (different `source`), intentionally, since the fix verification differs.

### Row semantics

`count` = total occurrences since `first_seen`. `last_seen` = most recent occurrence
(also the pruning key — a row disappears 30 days after its *last* occurrence, so
recurring errors never age out). `reason` is truncated at 2000 chars, `stacktrace`
at 8000.

### Reliability properties

Telemetry handlers only do a `GenServer.cast` (non-blocking, can't slow the failing
request further); the upsert happens in the ErrorTracker process wrapped in
try/rescue, so a DB outage degrades to `[ErrorTracker] Upsert failed:` log lines
instead of crashing (and telemetry never detaches the handler).

**Not captured, even though it's supervised:** background work spawned via
`Task.Supervisor.start_child/2` (e.g. `Meta.enrich_visit_country`, and generally
anything under `Mehungry.TaskSupervisor` / `MehungryWeb.TaskSupervisor`) is
*supervised*, so a crash there is contained and logged by OTP's crash reporter —
but it isn't one of the three telemetry sources above, so it never becomes an
`error_events` row.

---

## 5. Log reference (stdout → ECS → CloudWatch)

| Prefix | Threshold | Emitted by | Example |
|---|---|---|---|
| `[ProcessWatchdog]` | mailbox ≥ 1000 | `MehungryWeb.Telemetry` poller (10 s) | `[ProcessWatchdog] Mailbox over 1000: #PID<0.1234.0> [registered_name: MehungryWeb.IngredientSearch, ...]` |
| `[ErrorTracker] Upsert failed:` | — | ErrorTracker | error tracking itself failed (usually DB down) |
| `[MetricsBuffer] Flush failed:` | — | MetricsBuffer | `telemetry_snapshots` write failed (window's data lost) |
| `[MetricsBuffer] Query flush failed:` | — | MetricsBuffer | `query_time_profiles` write failed (window's data lost) |
| `[MetricsBuffer] Timeline trim failed:` | — | MetricsBuffer | in-memory timeline trim failed (non-fatal, just means stale entries linger) |
| `[TelemetryPrunerWorker] Deleted ...` | daily | pruner | retention confirmation — absence for days means cron isn't running |

**There is no `[SlowQuery]` or `[SlowRequest]` log line.** Those were emitted by
`SlowQueryLogger`/`SlowRequestLogger`, both removed. Slow queries now surface by
opening the Queries or Query Timeline dashboard tab, or querying
`telemetry_snapshots`/`query_time_profiles` directly (§7); slow
requests/LiveView callbacks via the Endpoints tab or a direct query. There is no
passive, grep-the-logs way to notice either one — see §8.

**CloudWatch Logs Insights starters** (against the ECS task log group):

```
fields @timestamp, @message | filter @message like "[ProcessWatchdog]" | sort @timestamp desc
fields @timestamp, @message | filter @message like "[ErrorTracker]" | sort @timestamp desc
fields @timestamp, @message | filter @message like "[MetricsBuffer]" | sort @timestamp desc
```

Locally: `grep "\[ProcessWatchdog\]"` the server output.

---

## 6. Diagnostic playbooks

### 6.1 "The site feels slow"

1. **Endpoints tab** (24h): which `view`/`route` has the bad p95? Then look at
   `live_view.handle_event.duration` rows for laggy interactions specifically.
2. **Query Timeline tab**: filter to the relevant window, find the action group for
   the slow view/event, expand it — a high query count or one dominant slow query
   points straight at the database. An empty or fast query group means the time is
   in Elixir: rendering huge assigns, or an external HTTP call made inline instead
   of via Oban.
3. **Queries tab**: if the slow view's tables show high p95 there too, it's a
   systemic DB issue (→ 6.2), not just this one action.
4. **`mehungry.vm.scheduler.utilization`** — now persisted (§7 query, or watch
   live on the Metrics tab): if utilization is pinned high, it's not one view —
   the whole node is CPU starved (→ 6.5). `vm.total_run_queue_lengths.total`
   remains live-only, so cross-check that one live only.

### 6.2 "Database is degrading"

1. **`mehungry.repo.query.queue_time`** rising — now persisted, pull a trend from
   `telemetry_snapshots` (§7) instead of only catching it live. Rising →
   **pool exhaustion**: check `mehungry.repo.pool.busy`/`.total` (§3.11) for
   confirmation, and Ecto Stats → *Long running queries* / *Locks* for the
   culprit. Common causes: a migration holding a lock, a transaction wrapping an
   external call.
2. **`mehungry.repo.query.total_time`** rising for a specific `source`? — now
   persisted per source, so you can confirm this is sustained rather than a
   blip. Ecto Stats → *Seq scans* (missing index?), *Index cache hit* (working
   set outgrew RAM?). Get the actual SQL from the **Queries** tab (via
   `query_time`, persisted separately), then run it through
   `Mehungry.SqlUtils.explain_analyze/3` in `iex` directly.
3. Everything slow at once with queue_time flat → the RDS instance itself (check
   AWS RDS metrics: CPU, IOPS, freeable memory).

### 6.3 "Users report errors" / 5xx spike

1. **`phoenix.request.count`** filtered to `status: "5xx"` on the live Metrics
   tab (still no historical rate — §3.3, deferred): what share of current
   traffic is failing right now?
2. **Errors tab**: sort is already newest-first. High-`count` rows are your
   culprits. Expand → stacktrace points at the app frame; `context` gives
   route/view/event.
3. Match `first_seen` against deploy times — a fingerprint born minutes after a
   deploy is that deploy's regression.
4. Errors *not* on the Errors page but reported by users → likely a class the
   tracker doesn't see (§4, §8): a `Task.Supervisor` child crash, a plain
   GenServer crash, or something crashing before router dispatch. Check
   CloudWatch for OTP crash reports (no dedicated prefix — search for `** ` or
   `GenServer` around the reported time).

### 6.4 "Background work isn't happening"

1. **`mehungry.oban.queue.depth`** — now persisted (with the caveat in §3.5 that
   a queue at 0 depth produces no sample, not a 0-valued one): growing = jobs
   stuck/waiting; a gap in the historical trend at 0 depth is expected, not
   missing data.
2. **Errors tab, source=oban**: failing worker + stacktrace + attempt number.
3. **`oban.job.duration`** p95 per worker — now persisted, query
   `telemetry_snapshots` (§7) for a trend instead of only watching live: jobs
   slowing toward their timeout (AI calls have 90 s HTTP timeouts, generation
   `Task.async_stream` kills at 180 s) will start failing at the cliff.
4. In iex on the node: `Oban.check_queue(queue: :ai_agents)` for live state.
   Orphans from a dead node are rescued by Lifeline after 24 h; completed jobs are
   pruned after 24 h, so investigate failures within a day or rely on the Errors
   tab (30 d).

### 6.5 "Memory keeps growing" / "node is stuck"

1. **`vm.memory.total`** — now persisted, pull a 7-day trend directly from
   `telemetry_snapshots` (§7) instead of relying on the ECS/CloudWatch container
   metric as a proxy (that's still a fine cross-check, just no longer the only
   option). Sawtooth = fine; staircase = leak.
2. **`mehungry.cache.size`** — now persisted per cache: is `cache_user_tokens`
   (unbounded) the staircase? Query it directly rather than checking by eye.
3. **`mehungry.vm.process.max_message_queue`** + `[ProcessWatchdog]` logs: the
   watchdog names the process (registered name, initial call, current
   function). The named GenServer is processing slower than its inbox fills —
   its `current_function` tells you what it's stuck on.
4. **Processes tab**: sort by Memory / Message queue live; click a process for its
   state.
5. **`mehungry.vm.scheduler.utilization`** sustained above ~80% with normal
   memory = CPU saturation: too much concurrent work on the ECS task size
   (profile the hot views/jobs, or scale the task). Now persisted, so confirm
   "sustained" with a trend query rather than a few live samples. If
   `mehungry.vm.scheduler.weighted` is much higher than `.utilization`, the load
   is on dirty schedulers — NIF work like image processing, not Elixir code.

### 6.6 "Did the deploy make things worse?"

Compare Endpoints tab 24h (post-deploy) against 7d (baseline) for
`live_view.mount.duration` / `live_view.handle_event.duration` / `phoenix.request.duration`
p95, and the Queries tab for `query_time` regressions per statement. Then query
`telemetry_snapshots` directly (§7) for `mehungry.repo.query.total_time`/
`.queue_time`, `oban.job.duration`, `mehungry.vm.scheduler.utilization`, and
`vm.memory.total` — same 24h-vs-7d comparison, now possible for all of them.
New Errors-tab fingerprints with `first_seen` after the deploy are the smoking
gun. Also check the Query Timeline tab live for a few minutes post-deploy — a new
N+1 pattern shows up immediately as an outsized query group.

---

## 7. Operations

### Querying persisted metrics directly (no dashboard page yet for most of them)

Most metrics now flow into `telemetry_snapshots`, but only three (`phoenix.request.duration`,
`live_view.mount.duration`, `live_view.handle_event.duration`) have a dashboard
page (Endpoints). For everything else, query the table directly from
`iex -S mix phx.server` (or psql):

```elixir
import Ecto.Query

Mehungry.Repo.all(
  from s in Mehungry.Telemetry.Snapshot,
    where: s.metric == "mehungry.repo.query.total_time" and s.period_start > ago(1, "day"),
    order_by: [desc: s.period_start]
)
```

`tags` is a jsonb map (e.g. `%{"source" => "recipes"}`, `%{"queue" => "default", "worker" => "..."}`,
`%{"cache" => "recipes_cache"}`) — filter on it with a fragment if narrowing to
one tag value. Untagged metrics (`mehungry.vm.scheduler.*`, `vm.memory.total`,
`mehungry.vm.live_view.count`, `mehungry.repo.pool.*`, `mehungry.vm.process.*`)
have `tags == %{}`.

**Still genuinely not queryable, live or historical:** `phoenix.request.count`,
`phoenix.endpoint.duration`, `vm.total_run_queue_lengths.*` — these three have no
`MetricsBuffer` handler yet (§9).

### Retention & storage

- All three tables (`telemetry_snapshots`, `error_events`, `query_time_profiles`)
  pruned daily at **03:00 UTC** (`TelemetryPrunerWorker`, cron in
  `config/config.exs`); cutoff 30 days (`@retention_days`). The in-memory Query
  Timeline is separate — see below.
- Growth estimate, revised now that ~13 metric families persist instead of 3:
  rows per flush ≈ number of distinct `{metric, tags}` pairs active in the
  window. The untagged metrics (`vm.memory.total`, `mehungry.vm.scheduler.*`,
  `mehungry.vm.process.*`, `mehungry.vm.live_view.count`,
  `mehungry.repo.pool.*`) contribute a fixed ~9 rows/flush regardless of load.
  The tagged ones scale with cardinality: `mehungry.cache.size` adds 3 (one per
  cache), `mehungry.oban.queue.depth` adds up to 3 (one per active queue),
  `oban.job.*` adds one row per distinct `{queue, worker}` combination actually
  active in the window (bounded by the number of distinct worker modules, likely
  a few dozen), and the original route/view/event-tagged trio still dominates
  (expect roughly 50–150). All told, expect on the order of 100–250 rows per
  5-min flush — roughly double the pre-this-pass estimate, still comfortably
  under 100k rows/day (288 flushes/day × ~200 rows ≈ 58k/day, ~1.7M rows /
  30-day retention at steady state). Revisit if that becomes uncomfortable
  (raise the flush interval, or drop the least-useful untagged metrics).
- `query_time_profiles` grows separately, one row per distinct query fingerprint
  per 5-min window it fires in — expect this to track the number of distinct query
  shapes in the codebase, but the SQL text column makes each row heavier. Watch
  this table's size independently if it becomes a concern.
- The Query Timeline is in-memory (ETS) only, never persisted, and self-trims to
  the last 60 minutes on every 5-minute flush tick — it has no storage cost
  beyond RAM and no retention knob beyond `@timeline_retention`.

### Knobs (all module attributes / config)

| Knob | Where | Current |
|---|---|---|
| Flush interval | `MetricsBuffer` `@flush_interval` | 5 min |
| Query Timeline retention | `MetricsBuffer` `@timeline_retention` | 60 min |
| Query text truncation | `MetricsBuffer` `@query_text_limit` | 1000 chars |
| Error reason truncation | `ErrorTracker` `@reason_limit` | 2000 chars |
| Error stacktrace truncation | `ErrorTracker` `@stacktrace_limit` | 8000 chars |
| Mailbox threshold | `MehungryWeb.Telemetry` `@message_queue_threshold` | 1000 |
| Poller period | `MehungryWeb.Telemetry` `init/1` | 10 s |
| DB pool size (read live, not hardcoded) | `Mehungry.Repo.config()[:pool_size]` | 10 (dev hardcoded; prod via `POOL_SIZE` env, default 10) |
| Retention (snapshots/errors/query profiles) | `TelemetryPrunerWorker` `@retention_days` | 30 d |
| Errors page size | `ErrorsPage` `@limit` | 100 |
| Admin email | `config :mehungry, :admin_email` | — |

### Local testing recipes (iex -S mix phx.server)

```elixir
# Force a snapshot flush instead of waiting 5 minutes:
send(Mehungry.Telemetry.MetricsBuffer, :flush)

# Produce a slow query — now persists to BOTH mehungry.repo.query.total_time/
# queue_time (generic snapshot) and query_time (Queries tab / Query Timeline):
Ecto.Adapters.SQL.query!(Mehungry.Repo, "SELECT pg_sleep(1)")

# Produce a real Oban job execution (oban.job.duration/.queue_time):
Oban.insert!(Mehungry.ObanWorkers.TelemetryPrunerWorker.new(%{}))

# Produce an error-tracker row AND an oban.job.exception.count sample
# (fires the real Oban exception event):
:telemetry.execute([:oban, :job, :exception], %{duration: 1},
  %{kind: :error, reason: %RuntimeError{message: "test"},
    stacktrace: [{Mehungry.Fake, :boom, 1, []}],
    job: %Oban.Job{worker: "TestWorker", queue: "default", attempt: 1}})

# Trip the process watchdog (warning within 10 s):
pid = spawn(fn -> Process.sleep(:infinity) end)
for i <- 1..2000, do: send(pid, {:flood, i})

# Run the pruner immediately:
Oban.insert!(Mehungry.ObanWorkers.TelemetryPrunerWorker.new(%{}))

# Force a query-time profile flush and inspect the result:
send(Mehungry.Telemetry.MetricsBuffer, :flush)
Mehungry.Repo.all(Mehungry.Telemetry.QueryProfile)

# Inspect the live, unpersisted Query Timeline (last 15 minutes):
Mehungry.Telemetry.MetricsBuffer.list_recent_query_events(15)

# EXPLAIN ANALYZE a query copied from the Queries or Query Timeline tab:
Mehungry.SqlUtils.explain_analyze(
  "SELECT r0.\"id\" FROM \"recipes\" AS r0 WHERE r0.\"user_id\" = $1",
  [123]
)

# Cross-check the pool gauge against ground truth:
Ecto.Adapters.SQL.query!(Mehungry.Repo,
  "SELECT count(*) FILTER (WHERE state='active') AS busy, count(*) AS total FROM pg_stat_activity WHERE datname = current_database()")

# Inspect every newly-persisted metric after a forced flush:
send(Mehungry.Telemetry.MetricsBuffer, :flush)
import Ecto.Query
Mehungry.Repo.all(
  from s in Mehungry.Telemetry.Snapshot,
    where: s.metric in [
      "mehungry.repo.query.total_time", "mehungry.repo.query.queue_time",
      "oban.job.duration", "oban.job.queue_time", "oban.job.exception.count",
      "mehungry.cache.size", "mehungry.oban.queue.depth",
      "mehungry.vm.process.max_message_queue", "mehungry.vm.process.over_threshold_count",
      "mehungry.vm.scheduler.utilization", "mehungry.vm.scheduler.weighted",
      "vm.memory.total", "mehungry.vm.live_view.count",
      "mehungry.repo.pool.busy", "mehungry.repo.pool.total", "mehungry.repo.pool.pool_size"
    ],
    order_by: [desc: s.period_start]
)
```

### Deploy notes

- Migrations `20260630000001_create_telemetry_snapshots`,
  `20260704000001_create_error_events`, and
  `20260704000002_create_query_time_profiles` must run (migrator ECS task). No
  new migration for this pass — the schema was already generic enough.
- No new env vars. No new runtime deps.
- The new pool-utilization poller adds one extra `pg_stat_activity` query every
  10s (catalog-only, cheap) — no RDS parameter group changes needed for it,
  unlike `pg_stat_statements` below.
- `pg_stat_statements` on RDS (parameter group + reboot) is optional but unlocks
  the best Ecto Stats panels (`outliers`, `calls`).

---

## 8. Limitations — know what you can't see

1. **Up to 5 minutes of metrics/query-profile data lost on crash/deploy**, and up
   to **60 minutes of Query Timeline data** lost on crash/deploy (it's ETS-only
   with no snapshot mechanism at all). Historical `telemetry_snapshots`/
   `query_time_profiles` rows already flushed are unaffected. This now applies to
   ~13 metric families instead of 3, so a crash loses a slightly larger, but
   still bounded, slice of data.
2. **No node dimension.** On multi-node ECS each node flushes its own rows into the
   same table with identical tags, and each node's Query Timeline is separate and
   only visible from that node's own dashboard session. Aggregates are per-node
   truths interleaved — fine for trends, misleading if one node is sick while
   others are healthy. Now also applies to the pool-utilization gauge
   specifically: each node's `pg_stat_activity` query sees the *whole database's*
   connections, not just its own — so on multi-node ECS, every node's
   `mehungry.repo.pool.total` reads the same combined number, not a per-node
   figure. (Top proposal in §9.)
3. **Dashboard-only: nothing pushes to you, and nothing passively logs either.**
   By explicit choice there is no alerting, and there's no `[SlowQuery]`/
   `[SlowRequest]` log fallback (§5). An error spike, a slow query, or a stuck
   LiveView at 02:00 waits until someone opens `/dashboard` or runs a manual
   query; `[ProcessWatchdog]` is the only passively-logged warning signal.
4. **Error tracker blind spots:** it only sees three telemetry sources (§4).
   Missed: plain GenServer crashes (e.g. `IngredientSearch`, Presence handlers),
   `Task.Supervisor` child failures (contained and logged by OTP, but not
   fingerprinted), channel/socket errors, anything crashing before router
   dispatch (plugs in the endpoint), and errors swallowed by `rescue`.
5. **Three metrics remain genuinely live-only**: `phoenix.request.count`,
   `phoenix.endpoint.duration`, and `vm.total_run_queue_lengths.*`. Everything
   else that used to be in this bucket earlier the same day is now persisted
   (§1, §3). These three are deferred, not forgotten — §9 has the shape of the
   fix for `phoenix.request.count` specifically.
6. **No dashboard page for most of what's now persisted.** The Endpoints/Queries
   tabs only cover the original three metrics and the query-fingerprint table.
   `mehungry.cache.size`, `oban.job.*`, `mehungry.oban.queue.depth`,
   `mehungry.vm.*`, and `mehungry.repo.pool.*` all have real history now, but no
   page renders it — you query `telemetry_snapshots` directly (§7). A generic
   metric-history browser page is now more valuable than it would have been
   before this pass (there's finally data for it to show) — see §9.
7. **The pool-utilization gauge assumes single-tenant database access** (§3.11)
   — confirmed true for this deployment, but if that ever changes, `total`
   overcounts relative to this app's actual pool usage.
8. **p95 is per-window.** Cross-window aggregation of percentiles is
   mathematically invalid; the Endpoints/Queries tabs handle this correctly
   (worst window in range), but any ad-hoc query against `telemetry_snapshots`
   needs the same care.
9. **Correlation is action-scoped, not request-scoped, and only for queries.** The
   Query Timeline (§3.9) ties queries to the action that fired them, but only for
   the last 60 minutes, only on one node, and only for queries — HTTP/LiveView
   durations, errors, and everything else still correlate only by eyeballing
   timestamps. There's still no `request_id` attached to metrics or errors, and no
   per-user attribution anywhere (also the privacy-friendly default).
10. **LiveView coverage gaps.** `handle_info` duration is not measured at all (not
    even in the Query Timeline — `ActionContext` doesn't attach to it, so its
    queries land under `"background"`); `handle_params` duration is likewise
    unmeasured as a metric, though its queries *are* correctly labeled in the
    Query Timeline. A slow PubSub-driven update is invisible except via user
    perception and `vm.total_run_queue_lengths`.
11. **10 s watchdog sampling** misses mailboxes that spike and drain between
    polls; the 1000 threshold is static and arbitrary. Same sampling-gap caveat
    now applies to `mehungry.vm.live_view.count` — a burst of connect/disconnect
    activity between two 10s samples isn't captured.
12. **View tag ambiguity.** `live_view.*` metrics and the Query Timeline's action
    labels alike tag the module *basename*, so `PostLive.Index` and
    `CalendarLive.Index` collide as `Index`.

---

## 9. Next steps (proposed, in priority order)

| # | Proposal | Effort | What it buys |
|---|---|---|---|
| 1 | **Add `phoenix.request.count`**: derive a status class (`2xx`/`4xx`/`5xx`/`unknown`) from `metadata[:conn].status` on `[:phoenix, :router_dispatch, :stop]` (guard the halted/`status == nil` edge case), add a matching `counter(...)` to `metrics/0`, and a `MetricsBuffer` handler | Small | Closes the last HTTP gap in limitation #5 — a durable 5xx-rate trend, not just individual fingerprinted errors |
| 2 | **A generic metric-history browser page** for everything now persisted but not on a dashboard page (`cache.size`, `oban.*`, `mehungry.vm.*`, `mehungry.repo.pool.*`) — metric dropdown + range picker, reading `telemetry_snapshots` directly | Medium | Closes limitation #6. More valuable now than when first proposed, since the data exists to show |
| 3 | **Persist `vm.total_run_queue_lengths.*`** — same shape as the `vm.memory.total` handler already added, just the other telemetry_poller default-global-instance event | Small | Closes the last VM gap in limitation #5 |
| 4 | **Add `node` to snapshot/error tags** (`System.get_env("HOSTNAME")` or `node()` at flush/upsert) | Small | Correct multi-node interpretation; spot a single sick ECS task; also disambiguates the pool gauge across nodes (limitation #2) |
| 5 | **Use full module path in `view` tags** (`inspect(view)` minus `MehungryWeb.` prefix) | Small | Fixes the `Index` collision (#12). Costs a bit of tag cardinality, still bounded. Applies to both `MetricsBuffer` and `ActionContext`'s `view_name/1` |
| 6 | **`:logger` handler → ErrorTracker** (a `:logger` handler that forwards crash reports for otherwise-untracked processes, including `Task.Supervisor` children) | Medium | Closes most of blind spot #4: GenServer/Task crashes become fingerprinted rows |
| 7 | **Measure `handle_params`/`handle_info` durations** (extend `MetricsBuffer` with the corresponding `:stop` events, and attach `ActionContext` to `handle_info`) | Small | Closes #10; PubSub-driven slowness becomes visible, and its queries stop landing in `"background"` on the Query Timeline |
| 8 | **`pg_stat_statements` on RDS** | Ops only | Ecto Stats `outliers`/`calls`: cumulative-cost query ranking — the single best slow-query tool available here |
| 9 | **Lightweight, opt-in slow-op log line** — a thin re-add of a threshold check (no dedicated GenServer needed, just a telemetry handler) purely to restore passive CloudWatch visibility, without resurrecting `SlowQueryLogger`/`SlowRequestLogger` wholesale | Small | Mitigates limitation #3 — only worth it if the dashboard-only workflow proves too slow to catch an incident in practice |
| 10 | **Persist a sampled slice of the Query Timeline** (e.g. one row per action per flush instead of per execution) | Medium | Extends N+1 debugging beyond the current 60-minute/single-node/in-memory window (§3.9) |
| 11 | **Threshold alert emails** via existing Swoosh + `mailers` queue (e.g. "5xx > 1% for 15 min", "queue depth > N for 30 min", with cooldown) | Medium | Closes #3 properly (push, not just passive log). Now unblocked for most metrics since they're persisted — still declined as a recommendation to build *now*, listed as the natural next step if an incident goes unnoticed for days |
| 12 | **Structured JSON logging** (`logger_json`) in prod | Medium | CloudWatch Insights can filter on fields instead of string matching; pairs well with `request_id` correlation (#9) |
| 13 | **External uptime check** on the existing `/health` endpoint (UptimeRobot free tier or a Route53 health check) | Ops only | The one failure mode nothing in-app can ever report: the app being down |

---

*Related design docs: `docs/secure_messaging_design.md`, `docs/scaling_metrics.md`.
Architecture overview: `CLAUDE.md`.*
