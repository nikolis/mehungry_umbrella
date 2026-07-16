# Scaling Metrics for Phoenix / Elixir in Production

What production Phoenix/Elixir teams watch to make scaling decisions — mapped against
the Mehungry telemetry stack: what we already capture, and the gaps that specifically
matter for **scaling** (as opposed to general debugging).

Last updated: 2026-07-05. Related: `docs/observability.md`.

**This pass closes most of what the previous version of this doc flagged as
missing.** `Mehungry.Telemetry.MetricsBuffer` now has handlers for scheduler
utilization, DB pool queue_time/total_time, Oban job duration/queue_time/
exceptions/queue depth, cache size, and VM memory — all of which were live-only
(or, for connection count and pool utilization, didn't exist at all) as of this
morning. Two brand-new gauges were added: a concurrent LiveView connection count
and a DB pool utilization gauge. A pre-existing bug was also fixed along the way:
the live Oban Metrics-tab charts were extracting tags from the wrong metadata
shape. See `docs/observability.md` §1/§3 for the full mechanism; this doc keeps
the same "have it?" framing as before so you can see exactly what moved.

---

## The framing: saturation is the scaling metric

Latency and errors tell you something is *already* wrong. For **scaling** — deciding
when to add a node, grow the DB pool, or resize the ECS task — the metric class that
matters is **saturation**: how close each finite resource is to its ceiling.

Below, everything is grouped by the resource whose ceiling you're watching. "Have it?"
distinguishes three states:

- ✅ **Persisted** — durable rows in `telemetry_snapshots`, has a real historical
  trend. (No dashboard page exists yet for most of these beyond the original
  Endpoints/Queries tabs — see `docs/observability.md` §7 for how to query them
  directly, and §9 proposal #2 for the page that should eventually exist.)
- ⚠️ **Live-only** — real data, sampled and visible on `/dashboard`'s live Metrics
  tab, but with no historical record; useless for retrospective analysis or an
  autoscaler unless someone happens to be watching at the right moment.
- ❌ **Not captured** — doesn't exist anywhere, live or otherwise.

---

## 1. CPU / scheduler saturation — the horizontal-scale trigger

*The* "add a node" signal on the BEAM.

| Metric | Why it's the scale trigger | Have it? |
|---|---|---|
| **Scheduler utilization** (`:scheduler.utilization/2`) | The correct BEAM CPU signal. OS load average lies on the BEAM because busy-waiting schedulers look "busy" at idle. Sustained >70–80% → scale out. | ✅ **Persisted** as `mehungry.vm.scheduler.utilization`/`.weighted`, untagged, every 5 min. Was live-only this morning |
| **Run queue length** (`vm.total_run_queue_lengths.*`) | Runnable processes waiting for a scheduler. >~2× core count sustained = CPU-starved. | ⚠️ Still live-only (`:telemetry_poller`'s own default global instance) — deliberately deferred alongside this pass, not forgotten |
| Reductions rate | Work throughput proxy; per-process hot-spot detection. | ⚠️ Live only (Processes tab), unchanged |

**What this closes:** scheduler utilization was previously "computed every 10s
but unexportable" — the fix was exactly what was proposed: a `MetricsBuffer`
handler on `[:mehungry, :vm, :scheduler]`. It's the single most useful new row
in this table — an ECS target-tracking policy or a Monday-morning trend review
can now actually read a `mehungry.vm.scheduler.utilization` series instead of
needing someone to be staring at the live dashboard at the right second.
Run-queue length remains the one CPU-saturation signal still stuck live-only;
same fix shape (`docs/observability.md` §9 proposal #3), just not done yet.

---

## 2. Concurrency / connection saturation — the LiveView blind spot, mostly closed

The app is almost entirely LiveView, which means **each active user is a long-lived
stateful process + a WebSocket**. This is the resource that actually caps how many
users a node holds.

| Metric | Why | Have it? |
|---|---|---|
| **Concurrent WebSocket / connected LiveView count** | Directly caps users-per-node. Drives the horizontal scaling decision for realtime apps more than CPU does. | ✅ **New this pass**: `mehungry.vm.live_view.count`, persisted every 5 min. Computed by extending the existing mailbox-watchdog process scan (`emit_process_stats/0`) to also tally processes whose `:proc_lib.translate_initial_call/1` resolves to `{_, :mount, 3}` — near-zero extra cost, no second VM walk |
| **Memory per connection** (total mem ÷ socket count) | Right-sizes the ECS task; catches assign bloat. | ⚠️ Not stored as its own metric, by design — now that both `vm.memory.total` and the connection count above are independently persisted, this ratio is derivable at analysis time without duplicating storage. If you want it as a first-class chart, that's a query/dashboard-page problem now, not a data-collection one |
| Process & port counts vs. limits | BEAM has hard ceilings (`+P`, default ~262k). Approaching = hard wall, not gradual. | ⚠️ Home tab live only, unchanged |

**What this closes:** this was the second-biggest named gap and is now fully
addressed for the count itself. Two things worth knowing: the gauge is
**poll-based, not event-counted** — deliberately, since Phoenix fires a
`[:phoenix, :socket_connected]` telemetry event on connect but nothing on
disconnect/terminate, so a connect-only counter could only grow. And it's
specifically LiveView (`:mount, 3`), not "any socket" — this app currently has
zero real `Phoenix.Channel` implementations wired up, so the distinction doesn't
matter yet, but the metric stays correct if that changes.

---

## 3. Database pool saturation — the gap that mattered most, now closed

Most Phoenix apps hit the DB pool wall long before CPU. Previously the worst
case in this document (live-only, and only emitted at all when already
nonzero); now the most improved section.

| Metric | Why | Have it? |
|---|---|---|
| **Pool checkout / queue time** (`mehungry.repo.query.queue_time`) | Rising queue_time with flat query_time = pool exhaustion. The classic "add connections or a node" signal. | ✅ **Persisted**, tagged by `source`. Still only recorded when > 0 (unchanged semantics), but now that sparse signal accumulates into a real trend instead of vanishing the moment nobody's watching |
| **Pool utilization** (busy/total connections vs. `pool_size`) | How close to `pool_size`. | ✅ **New this pass**: `mehungry.repo.pool.busy`/`.total`/`.pool_size`, persisted every 5 min. Computed via a `pg_stat_activity` query (same technique the already-installed `ecto_psql_extras` uses internally), not `DBConnection.get_connection_metrics/2` (rejected — needs the pool's internal pid, and only reports coarse whole-pool busy/ready state) |
| **Query time per source** (`mehungry.repo.query.total_time`) | Which table degraded. | ✅ **Persisted**, tagged by `source`. Distinct from per-*statement* `query_time` (already persisted separately via `query_time_profiles`, the Queries tab) — this one carries the pool-queue component that shape-level fingerprinting doesn't |
| RDS-side: CPU, IOPS, freeable memory, connection count | The DB's own ceiling. | ✅ AWS RDS metrics (external, unaffected) |

**Caveat on the new pool gauge:** it counts *all* connections to the database via
`pg_stat_activity`, not literally this app's Ecto pool checkouts — accurate only
if the database is single-tenant for this app. **Confirmed true** for this
deployment. If that ever changes (another service, a shared PgBouncer, ad-hoc
`psql` sessions during an incident), the gauge would overcount and need
`application_name`-based filtering.

**What this closes:** all three items named in the previous version's "worst
case in the doc" callout are now durable. This is arguably the highest-value
close in this whole pass — DB pool exhaustion is the single most common
Phoenix-app scaling wall, and it went from "only visible if you're staring at
the dashboard at the exact moment" to "query a week of `queue_time`/`total_time`/
`pool.busy` trends whenever you want."

---

## 4. The golden signals (traffic / latency / errors)

Standard Google-SRE four, framed for capacity. Least changed section — the one
deferred item (`phoenix.request.count`) lives here.

- **Throughput (req/s, and events/s over the socket).** Per-route/per-view
  throughput is still *derivable* historically from `# Samples ÷ 300` on
  `phoenix.request.duration`/`live_view.mount.duration`/
  `live_view.handle_event.duration` — unchanged, already solid. Total request
  volume and status-class breakdown (`phoenix.request.count`) is **still
  ⚠️ live-only** — this is the one item explicitly deferred this pass (it needs
  new status-classification logic, not just wiring an existing event; see
  `docs/observability.md` §9 proposal #1). `phoenix.request.*` still sees
  **none** of post-mount LiveView navigation (it's all WebSocket) — a LiveView
  event rate remains a genuinely new metric to add, unaffected by this pass.
- **Latency p95/p99 per route & per LiveView mount/handle_event.** ✅ Unchanged
  — still the strongest metric class, still no **p99** (out of scope for this
  pass, not selected). p95 also can't be cross-window aggregated
  (`docs/observability.md` §3.1).
- **Error rate (5xx share).** ⚠️ Unchanged, still split: individual failures are
  durably fingerprinted on the Errors tab, but the *rate* — `phoenix.request.count`
  filtered to `5xx` ÷ total — remains live-only until proposal #1 lands.

---

## 5. Background-work saturation (Oban) — now solidly covered, including the one item that was missing entirely

| Metric | Have it? |
|---|---|
| **Queue depth** (`mehungry.oban.queue.depth`) | ✅ **Persisted**, tagged by `queue`. One caveat carried over from the emitter's existing behavior: a queue at 0 depth for the whole window produces *no row*, not a 0-valued one — a gap in the trend at zero depth is expected, not missing data |
| **Job execution time** (`oban.job.duration`) | ✅ **Persisted**, tagged by `queue`/`worker` |
| **Exception rate** (`oban.job.exception.count`) | ✅ **Persisted**, tagged by `queue`/`worker` — a genuine counter (min/avg/max/p95 all 1.0, `# Samples` is the count) |
| **Time-in-queue / scheduling latency** (enqueue→execute gap) | ✅ **Persisted** as `oban.job.queue_time` — this came along for free: Oban's `[:oban, :job, :stop]` event's `:queue_time` measurement *is* exactly this gap, and it was captured in the same handler as `oban.job.duration`. Previously listed as "still missing entirely" — it no longer is |

**Bug fixed along the way:** the live Metrics-tab entries for
`oban.job.stop.duration`, `oban.job.stop.queue_time`, and
`oban.job.exception.count` declared `tags: [:queue, :worker]` without telling
`Telemetry.Metrics` how to extract them — Oban nests those fields under
`metadata.job`, not top-level, so the live charts were almost certainly
rendering blank/missing tags before this fix (`docs/observability.md` §3.5).

**What's left:** nothing named in the original gap list. If you want more here,
the next thing worth asking for is a dashboard page (§9 proposal #2 in
`docs/observability.md`) rather than more instrumentation.

---

## 6. Memory & leak detection — the total is covered, the breakdown still isn't

- `vm.memory.total` — ✅ **Persisted** now (was live-only this morning). A
  7-day trend is a direct query away (`docs/observability.md` §7); the
  ECS/CloudWatch container memory metric remains a valid external cross-check
  but is no longer the *only* option.
- The **breakdown** (process / binary / ETS / atom) is what tells you *which*
  leak, and it's still missing — `vm.memory.total` is a single number even
  now that it's persisted. Binary leaks and ETS growth are the two classic BEAM
  production issues; total memory alone still can't distinguish them. Partial
  mitigation: `mehungry.cache.size` (the ETS ingredient/user-token/geo caches)
  is now persisted too, so at least that slice of "which ETS table is growing"
  is answerable without the full breakdown.
- Atom count vs. limit — hard ceiling, crashes the node. ⚠️ Home tab live only,
  unchanged.

---

## Bottom line for this app

**What changed:** three of the four gaps named in the previous version's bottom
line are now closed or substantially addressed. CPU (scheduler utilization), DB
pool (queue_time, total_time, and the new utilization gauge), and Oban (depth,
duration, exceptions, *and* scheduling latency) all moved from live-only/missing
to durably persisted. The concurrent-connection gauge — previously entirely
absent — now exists.

**What's still open, in priority order:**

1. **`phoenix.request.count`** — the last HTTP gap. Needs a status-class
   derivation from `conn.status`, not just wiring; small, well-scoped, deferred
   this pass on purpose (`docs/observability.md` §9 proposal #1).
2. **`vm.total_run_queue_lengths.*` persistence** — same handler shape as
   `vm.memory.total` (already done), just not selected for this pass
   (`docs/observability.md` §9 proposal #3).
3. **p99 latency and a first-class LiveView event throughput counter** — layered
   on top of the metric class that already persists correctly
   (`phoenix.request.duration`/`live_view.*.duration`); out of scope for both
   this pass and the previous one.
4. **Memory breakdown by category** (process/binary/ETS/atom) — `vm.memory.total`
   alone still can't distinguish a binary leak from ETS growth; `cache.size`
   covers part of the ETS side but not the rest.
5. **A generic metric-history dashboard page** — everything above (and
   everything closed in this pass) is queryable via `telemetry_snapshots` today,
   but only the original three HTTP/LiveView metrics have an actual dashboard
   page (Endpoints). A metric-dropdown-plus-range-picker page reading the table
   directly would make all of this pass's new data usable without writing a
   query every time (`docs/observability.md` §9 proposal #2).
6. **Node dimension** — on multi-node ECS, every node's flush interleaves into
   the same rows with identical tags; this also now applies to the new pool
   gauge specifically, since `pg_stat_activity` sees the whole database's
   connections regardless of which node asked.

None of these six require new architecture — items 1–2 are the same
`MetricsBuffer`-handler pattern used throughout this pass, item 5 is a LiveView
page over data that already exists, and item 6 is a tag addition at flush/upsert
time.

---

*Sources: Google SRE golden signals + the BEAM-specific saturation signals that the
Elixir observability ecosystem (`telemetry_metrics`, `PromEx`, Phoenix's own
`telemetry.ex` template) standardizes on, cross-checked against the actual
`Mehungry.Telemetry.MetricsBuffer` handler list and verified end-to-end against a
running instance rather than assumed from documentation.*
