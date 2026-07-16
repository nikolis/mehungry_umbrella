# Observability Stack Review — 2026-07-05

Review of the telemetry/observability stack: `apps/mehungry/lib/mehungry/telemetry/*`, `apps/mehungry_web/lib/mehungry_web/telemetry.ex`, the four admin LiveDashboard pages, the pruner worker, migrations, and `docs/observability.md`.

## Context

Notable finding: **almost none of this is committed.** Only 4 commits (`9168ef5a`, `7433f211`, `5792ba98`, `eef2dc84`, all within ~1 hour on 2026-06-30) exist in git history for this area. Everything else — `error_tracker.ex`, `metrics_buffer.ex`, `snapshot.ex`, `query_profile.ex`, `error_event.ex`, `action_context.ex`, the pruner worker, all 3 migrations, all 4 dashboard LiveView pages, `require_admin.ex`, and `docs/observability.md` — was uncommitted working-tree state as of this review.

## Pros

1. **Clean fan-out architecture.** Telemetry events fan out to 3 independent consumers (live `MehungryWeb.Telemetry` metrics/poller, `MetricsBuffer` persistence, `ErrorTracker`) via ordinary `:telemetry.attach`, all under `:one_for_one` supervision — a crash in one never affects the others.
2. **Smart fingerprinting.** `ErrorTracker` fingerprints on `{source, kind, exception type, first app stack frame}`, deliberately excluding message text (avoids param-driven fingerprint fragmentation). `MetricsBuffer` fingerprints queries on `sha256(source|query_text)` for per-shape profiling.
3. **`ActionContext` correlation** is a lightweight, zero-dependency way to tag raw query samples with the HTTP route/LiveView event/Oban job that triggered them — useful for the Query Timeline page, achieved with `Process.put`/telemetry span hooks rather than a heavy APM.
4. **Reasonable retention story.** 30-day Postgres retention via `TelemetryPrunerWorker` (Oban cron `0 3 * * *`) matches doc claims exactly; 60-min in-memory timeline via `MetricsBuffer.trim_timeline/0`. Indexes mostly match query access patterns (`[:metric/:fingerprint, :period_start]`, `unique_index` on `fingerprint`, index on `last_seen`).
5. **Sensible admin security posture.** `RequireAdmin` plug returns 404 (not 403/redirect) so non-admins can't confirm the route exists — a deliberate, documented choice.
6. **Proportionate to project scale.** No new external dependencies/cost (no Sentry, no Datadog) — matches a solo-operator project's needs, and is explicitly documented as a deliberate tradeoff in `docs/observability.md`.
7. **Genuinely thorough documentation** (`docs/observability.md`) — rare for a project this size to have an operator's manual with a metric reference and diagnostic playbooks.

## Cons / Risks

1. **Uncommitted state is the biggest risk.** The entire system (bar 4 early commits) sits in the working tree. It hasn't been through review, and a stray `git checkout`/`reset` would silently resurrect the deleted `SlowQueryLogger.attach()` call in `application.ex` and lose everything else.
2. **Silent data truncation (real correctness bug).** `EndpointTimesPage` and `QueryTimesPage` both do `LIMIT 2000` in SQL, ordered by `p95` globally, *before* grouping down to "worst window per endpoint/fingerprint" in Elixir. For a busy 7-day range with many distinct routes/query shapes, this can silently drop entire endpoints/queries from the report — not paginate them away, just erase them — with zero indication to the admin.
3. **Silent error swallowing in the dashboard itself.** All four dashboard pages use bare `rescue _ -> []` with no logging. A DB timeout or pool exhaustion renders identically to "no data yet." This is ironic given the system's whole purpose is surfacing failures — the observability layer has no observability into its own failures (contrast with `MetricsBuffer.flush/0`, which does log on rescue).
4. **Inconsistent admin-gating mechanism.** `/dashboard` is gated by a one-shot `Plug` check at initial HTTP request time (no `on_mount` passed to `live_dashboard/2`, though it accepts one), while `/professional/*` re-verifies admin status via `on_mount: AdminAuthLive` on every mount/reconnect. Two different auth code paths for what is otherwise the same admin-only surface.
5. **`QueryTimelinePage` has no row cap.** Unlike the other 3 pages' `limit: 2000`, it does a full unbounded `:ets.tab2list` scan of the 60-minute window on every load — and LiveDashboard's refresh interval is admin-adjustable down to 1s, so this could re-scan a large ETS table once per second.
6. **Two decoupled "retention" systems.** The 30-day Postgres prune (Oban cron) and the 60-min ETS trim (GenServer timer) are unrelated mechanisms that happen to both be described as "retention" in the UI copy. They can drift or fail independently with no shared monitoring of "is pruning actually working."
7. **Unbounded prune deletes.** `TelemetryPrunerWorker` runs 3 unbounded `DELETE ... WHERE` statements on the shared `:default` Oban queue (10 concurrency, shared with app jobs) — at the doc's own estimated steady-state (~1.7M rows), this could be a long-running delete/lock, and it competes with regular application jobs rather than running on an isolated queue.
8. **No charting anywhere**, despite Vega-Lite being an established pattern elsewhere in this same app (`analytics_live.ex`, `seo_live.ex`, `pie_chart.ex`). All 4 telemetry pages are plain numeric HTML tables — trends require manually flipping time-range buttons and eyeballing numbers.
9. **Documentation reliability gap.** `docs/observability.md` contains a same-day self-correction admitting an earlier draft's claims were wrong, and references a `SlowRequestLogger` module that has **zero trace in git history** — either never actually committed or a documentation error.
10. **No alerting, by design.** Purely pull/dashboard-based. For a solo-operator app this may be acceptable, but it means incidents are invisible unless someone opens `/dashboard`.
11. **`ActionContext` doesn't propagate into `Task.async`.** Documented limitation, but a real gap — queries fired from AI agent async calls or `Task.Supervisor`-spawned work show up unlabeled as "background" in the Query Timeline.
12. **Minor cruft:** a leftover commented-out duplicate `# MehungryWeb.Telemetry,` line in `mehungry_web/application.ex`; a stale/misleading "dev-only, put behind auth" comment above the now-already-authenticated `live_dashboard` route; standalone `[:period_start]` indexes that are largely redundant prefixes of the composite indexes; no index on `p95` (the `ORDER BY` column on 2 of the 4 pages, currently low-risk at small scale).

## Missing

- **Alerting** — explicitly out of scope by choice; worth reconsidering given nothing pages anyone on failure.
- **Self-monitoring of the observability stack** — nothing detects "the pruner silently stopped running" or "MetricsBuffer's flush has been failing for 3 days."
- **Charting/trend visualization** on any of the 4 custom dashboard pages.
- **Correlation across async boundaries** (`Task.async`, async AI agent calls) in `ActionContext`.

## Useless / Questionable

- The standalone `[:period_start]`-only indexes are mostly-but-not-fully redundant with the composite indexes (they do still help pure period_start-only scans like the pruner's deletes) — minor, not worth ripping out, just worth knowing they overlap.
- `Oban.Plugins.Pruner` (built-in Oban job-table pruner) vs. `Mehungry.ObanWorkers.TelemetryPrunerWorker` (custom, prunes telemetry tables) is a confusing naming collision between two unrelated "pruners" — not useless, just a trap for future readers.

## Rating: 7/10

Strong architectural instincts for a solo-developer, self-hosted observability layer — proportionate scope, clean separation of concerns, thoughtful fingerprinting/dedup, real docs. Held back from a higher score by one genuine correctness bug (silent truncation), a systemic gap (the dashboard swallows its own errors silently), an inconsistent auth pattern, and — most urgently — the fact that essentially the entire system was sitting uncommitted in the working tree.

## Suggested priority order (if acting on this)

1. **Commit the working tree** (review the diff, then commit) — closes the biggest risk (loss of days of work) before anything else.
2. **Fix the `LIMIT 2000`-before-grouping truncation** in `EndpointTimesPage` and `QueryTimesPage` — either raise the limit, push the "max p95 per group" reduction into SQL (e.g. `DISTINCT ON`/window function), or explicitly cap+label truncation in the UI.
3. **Add logging to the `rescue _ -> []` blocks** in all 4 dashboard pages, matching the `Logger.error` pattern already used in `MetricsBuffer`.
4. **Decide on `/dashboard` auth consistency** — either pass `on_mount: RequireAdmin`-equivalent to `live_dashboard/2`, or explicitly document why the plug-only gate is sufficient (LiveDashboard sessions are typically short-lived, so this may be a non-issue — worth a conscious decision either way).
5. **Add a `limit` to `QueryTimelinePage`'s ETS scan**, or debounce/cache it, given it can run every 1s.
6. **Fix the `docs/observability.md` discrepancy** around `SlowRequestLogger`, and remove the stray commented-out line in `mehungry_web/application.ex`.
7. (Lower priority) Consider moving `TelemetryPrunerWorker` to a dedicated Oban queue, and revisit whether any alerting (even a simple "no data flushed in X minutes" self-check) is worth adding given the no-alerting design is otherwise a single point of blindness.
