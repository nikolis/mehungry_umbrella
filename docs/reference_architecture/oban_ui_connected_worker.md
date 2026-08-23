# Reference Architecture: Oban-backed, LiveView-connected batch worker

A reusable design pattern for **"kick off a large fan-out of background jobs from a
LiveView, then watch them finish live"** — durable, fault-tolerant, and cheap to
render even when thousands of jobs churn at once.

The canonical implementation is the **S3 → USDA ingredient seeding** flow. Use this
document as the template when you want the same shape for another feature (e.g.
"reprocess every recipe image", "re-crawl a corpus", "bulk re-embed").

## Cast of characters (canonical implementation)

| Role | Module | Responsibility |
|---|---|---|
| **LiveView** | `MehungryWeb.ProfessionalLive.S3BrowserLive` | Triggers the batch, subscribes to progress, renders the table |
| **Durable tracking schema** | `Mehungry.FoodData.Usda.SeedFile` | One row per unit of work; its `status` **is** the source of truth |
| **Query/command + broadcast layer** | `Mehungry.FoodData.Usda.SeedFiles` | Upsert/transition rows, emit PubSub, cancel jobs on reset |
| **Worker** | `Mehungry.ObanWorkers.SeedFileImportWorker` | One job == one unit of work; does the actual import |
| **I/O seam** | `Mehungry.FoodData.Usda.SeedFileFetcher` (`:seed_file_fetcher` config) | Network fetch, swappable in tests |
| **Dedicated queue** | `seed_imports` (concurrency 1) | Isolation from other background work |

The key architectural idea: **the LiveView never holds the work in memory and never
polls.** It enqueues jobs, subscribes to a PubSub topic, and patches individual table
rows as durable DB rows transition. The database row is the single source of truth;
the LiveView is a disposable view over it.

---

## 1) How the jobs are scheduled with Oban

### One job == one unit of work

`SeedFileImportWorker.perform/1` handles exactly one `{bucket, key}` file. Batches are
never a single mega-job — a 5,000-file bucket becomes 5,000 independent jobs. This is
what makes progress granular, retries surgical, and failures isolated (one bad file
doesn't sink the run).

### Enqueue creates the tracking row *first*

`enqueue/2` is the single entry point and it does two things, **in this order**:

```elixir
def enqueue(bucket, key) do
  seed_file = SeedFiles.upsert_pending(bucket, key)   # 1. durable row -> "pending" (+ broadcast)

  %{seed_file_id: seed_file.id, bucket: bucket, key: key}
  |> new()
  |> Oban.insert()                                     # 2. enqueue the job, carrying the row id
end
```

The tracking row is written to `pending` **before** the job exists, so the UI reflects
the queued state immediately — even if the job sits in the queue for a while. The job
args carry the `seed_file_id`, so the worker can find its row without re-deriving it.

### Idempotency and de-duplication (two layers)

- **DB layer:** `upsert_pending` uses `on_conflict: {:replace, ...}` on the
  `[:bucket, :key]` unique constraint. Re-enqueuing an existing file resets it to
  `pending` rather than creating a duplicate row.
- **Oban layer:** the worker declares `unique: [fields: [:args], keys: [:bucket, :key],
  states: [:available, :scheduled, :executing, :retryable]]`. Clicking "Load
  ingredients" twice, or a "Re-do" that races the batch, won't stack duplicate jobs for
  the same file while one is still live.

### Skip work already done

Before enqueuing a bucket, the candidate keys are filtered through
`SeedFiles.pending_or_failed/2`, which drops any key already `completed`. A re-click on
a half-finished run only enqueues the remainder. (Files with no row yet count as
undone.)

### Dedicated queue for blast-radius isolation

`SeedFileImportWorker` runs on its own `seed_imports` queue (concurrency **1**),
deliberately separate from the shared `imports` queue that the long-running science
pipeline uses. Rationale (from `CLAUDE.md`): a bulk "Load ingredients" run over a full
bucket must not **starve** behind — or be starved by — the self-resuming pipeline that
shares `:imports`. Total Oban concurrency across all queues is capped so job slots fit
inside the DB connection pool with headroom for web/LiveView.

> **Pattern rule:** a high-volume, user-triggered fan-out gets its **own queue** so it
> can neither starve nor be starved by unrelated background work. Size total
> concurrency against the DB pool, not in isolation.

### Batch the enqueue itself for large corpora

The "row first, then job" shape above is written per-unit for clarity, but **fanning
out a whole corpus one `Oban.insert` at a time is a load-bearing mistake at scale.**
Two costs compound over N units:

- **N × 2 DB round-trips** — a tracking-row upsert *and* a job insert per unit, all
  sequential (the enqueue loop runs on one process inside `start_async`).
- **N × `NOTIFY`** — Oban's `insert_trigger: true` fires a `NOTIFY` on **every**
  `Oban.insert`. Those all funnel through Oban's **single** notifier connection. A
  few-thousand-unit sweep in a tight loop can back that one connection up past the
  producers'/plugins' 5 s `:listen`/`:leader?` timeout and **cascade the whole Oban
  supervision tree down** — a real prod incident on 2026-08-19 (see
  `oban_production_diagnostics.md` §12).

So for a full-corpus fan-out, **batch both writes**:

```elixir
# 1. one INSERT ... ON CONFLICT for every tracking row, returning ids
def upsert_pending_all(unit_ids) do
  now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)   # match the schema's timestamp type
  rows = Enum.map(unit_ids, &%{unit_id: &1, status: "pending", inserted_at: now, updated_at: now})

  {_n, rows} =
    Repo.insert_all(Tracking, rows,
      on_conflict: {:replace, [:status, :updated_at]},
      conflict_target: [:unit_id],
      returning: [:id, :unit_id]
    )
  rows
end

# 2. one Oban.insert_all for every job (a single insert notification, not N)
def enqueue_all(unit_ids) do
  jobs = for %{id: id, unit_id: uid} <- upsert_pending_all(unit_ids),
             do: new(%{tracking_id: id, unit_id: uid})

  case Oban.insert_all(jobs) do
    inserted when is_list(inserted) -> length(inserted)
    _ -> 0
  end
end
```

Notes and trade-offs:

- **Drop the per-row `pending` broadcast in the batch path.** It's only safe to drop
  when the LiveView reflects the pending state another way — the canonical hashtag
  case tracks **aggregate counts** refreshed on a flush timer, and `handle_async`
  re-queries them once the enqueue returns, so N per-row "pending" pings would be
  redundant. If your LiveView instead streams each row individually and needs the
  pending row to appear before its first `processing` broadcast, either emit **one**
  batch signal or re-list once after enqueue — don't restore the per-row loop.
- **`Repo.insert_all` doesn't autogenerate timestamps and dumps against the schema's
  declared type** — pass `inserted_at`/`updated_at` explicitly, as the *right* type
  (`:naive_datetime` unless the schema says otherwise; a `DateTime` against a
  `:naive_datetime` column raises `Ecto.ChangeError`).
- **`Oban.insert_all` does not honour the worker's `unique` option** (only
  `Oban.insert` does). Filter already-queued/already-done units out *before* the
  batch (the `pending_or_failed` step below) rather than relying on Oban to dedupe.
- **Notifier choice is the deeper fix.** Switching Oban to `Oban.Notifiers.PG`
  (pub/sub over Erlang process groups, no DB socket) removes the NOTIFY-storm hazard
  entirely; batching is still worth it for the round-trip savings. See
  `oban_production_diagnostics.md` §12.

---

## 2) How progress is tracked & fault tolerance achieved

### The durable row is the source of truth

`SeedFile.status` moves through a small state machine, and every transition is a
**committed DB write** — not just an in-memory or PubSub event:

```
pending ──▶ processing ──▶ completed   (ingredient_count set)
                        └─▶ failed      (error set to inspected reason)
```

Because state lives in Postgres, it survives LiveView reconnects, server restarts, and
dropped PubSub messages. A freshly mounted LiveView reads current truth with
`SeedFiles.list_by_bucket/2` and is immediately correct — no replay needed.

### Transitions happen at the edges of the job

`SeedFileImportWorker.perform/1`:

1. `SeedFiles.mark_processing(id)` — right when the job starts.
2. Fetch via the seam → on error, `mark_failed` + return `{:error, reason}`.
3. Parse+insert in **a single transaction per file** → `mark_completed(id, count)` on
   success, `mark_failed` on error.

Returning `{:error, reason}` (rather than swallowing it) is deliberate: it lets **Oban
record the error and retry** up to `max_attempts: 3` with backoff. The `failed` status
is only the *terminal* state after retries are exhausted; a transient fetch blip
self-heals.

### Fault-tolerance properties, and how each is achieved

| Property | Mechanism |
|---|---|
| **Transient errors recover** | Worker returns `{:error, _}` → Oban retries (`max_attempts: 3`) |
| **Failures are visible, not silent** | `mark_failed` writes `error` (inspected reason); UI shows it in a `title=` tooltip. Explicitly replaces the earlier fire-and-forget worker that "tracked nothing and silently dropped failures" |
| **URLs can't expire in the queue** | Presigning happens **inside the job** (`SeedFileFetcher`), at fetch time — not in the LiveView. A short-lived URL minted before a long queue wait would be dead on arrival |
| **Reset never orphans jobs** | `SeedFiles.reset/2` calls `cancel_pending_jobs` (`Oban.cancel_all_jobs` scoped by queue + `args->>bucket` [+ key prefix]) **before** `delete_all`, so no job runs against a deleted row |
| **A job whose row vanished won't crash-loop** | `update_status/2` no-ops (returns `nil`, logs) if the row is gone — a `reset` mid-flight can delete a row under a running job; a raise would spin pointless retries |
| **Crash-safe progress** | Every status is a committed write; a server restart loses nothing, and Oban re-runs `executing` jobs that were interrupted |

> **Pattern rule:** the worker's return value is your retry contract. Return
> `{:error, _}` for anything retryable; only write a terminal `failed` status for the
> user to see, and let Oban decide when that terminal state is reached.

---

## 3) Interaction with the LiveView & the reasoning behind decisions

This is the subtle part and the reason the pattern exists. The LiveView must reflect a
high-frequency stream of updates **without** melting under render cost.

### Enqueue off the socket with `start_async`

"Load ingredients" runs its S3 list + fan-out enqueue inside `start_async`, so the
`loading` state actually renders during the (slow) S3 round-trip and the socket stays
responsive. The result lands in `handle_async(:load_ingredients, ...)`. Same pattern
for plain listing (`start_async({:list, ...})`).

> **Why:** never block the LiveView process on network I/O — the whole point of a
> connected process is that it can render intermediate states.

### Subscribe once per bucket; the row is a `stream` entry

On mount / when the browsed bucket changes, `ensure_subscribed/2` subscribes to
`SeedFiles.topic(bucket)` (and unsubscribes from the previous one). Table rows are a
Phoenix **`stream`** (`phx-update="stream"`), so a single row can be patched with
`stream_insert` as an **O(1) DOM diff** — the whole table is never re-rendered when one
file finishes.

### Two-tier broadcast: full row for terminal, lightweight signal for `processing`

This is the load-bearing decision. A bucket seed fans out thousands of jobs, each of
which flips to `processing` almost immediately. Broadcasting a full row for every
`processing` transition would flood the LiveView mailbox and force thousands of renders.

So the broadcast is **split by frequency**:

- **Terminal transitions** (`completed` / `failed`) — relatively rare, carry the real
  result — broadcast the **full row**: `{:seed_file, %SeedFile{}}`. The LiveView patches
  that one row and adjusts counts.
- **The `processing` transition** — extremely high-frequency, carries no result worth
  showing beyond "in flight" — emits an **identifiers-only** signal:
  `{:seed_file_processing, bucket, key}`. The `processing` DB write still happens (audit
  trail); only the *broadcast* is slimmed.

Because the row **always** moves on to a full-row `completed`/`failed` broadcast,
**nothing is lost if a `processing` signal is dropped**. The lightweight signal is a
best-effort "work is happening" hint, not a correctness-critical event.

### Coalescing: buffer `processing` signals behind a flush timer

The LiveView doesn't render per `processing` signal. It buffers keys into a `MapSet`
and arms a single `Process.send_after(self(), :flush_processing, @processing_flush_ms)`
(400 ms) timer:

```
{:seed_file_processing, ...}  ─▶ MapSet.put(processing_pending, key) ─▶ arm timer (once)
                                                                          │  (400ms)
:flush_processing  ◀───────────────────────────────────────────────────┘
   └─▶ apply every still-"pending" buffered key in ONE batched patch, then disarm
```

This bounds re-renders to roughly `1000 / @processing_flush_ms` per second (~2.5/s) no
matter how fast jobs churn. `arm_processing_flush/1` schedules at most once per window;
signals inside the window just accumulate.

### Server-side bookkeeping that never triggers a render

Two assigns are maintained **outside** the stream so updating them doesn't re-render the
table:

- **`file_index`** (`key => row map`) — holds the S3 metadata (size / last-modified /
  name) that a live status update lacks, so a `{:seed_file, ...}` broadcast (which only
  carries status fields) can be merged onto the full row before `stream_insert`.
- **`counts`** (`status => count`) — the summary line ("Pending 12 · Processing 3 ·
  Completed 90 · Failed 1"). Maintained **incrementally** via `adjust_counts/3`
  (decrement old bucket, increment new) so it never walks the whole listing on a
  broadcast.

> **Why keep a shadow `file_index`?** A stream is write-only from the server's
> perspective — you can't read a row back out of it. To *merge* a partial update onto a
> row you need the prior full row somewhere; that's the `file_index`. It's also what
> lets `reset-seed-status` clear statuses in place (strip fields, re-stream) without a
> re-list round-trip.

### Guard rails on incoming messages

`handle_info` for both signals ignores broadcasts that don't apply to the current view:
wrong bucket, or a key not on the current page (`file_index` miss). The `processing`
handler additionally only buffers keys still `pending` — if a terminal broadcast already
moved the row on, the stale `processing` hint is dropped.

### Observability niceties

The connected process sets an OTP label via `:proc_lib.set_label({:s3_browser_live,
bucket})` (guarded — OTP 27+ only) so a backed-up mailbox during a big run shows up as a
named process in observer / `:recon` / LiveDashboard rather than an anonymous pid.

---

## Distilling the pattern (checklist for reuse)

When you want this shape for a new feature, replicate these decisions:

1. **Durable tracking table**, one row per unit of work, with a small explicit `status`
   state machine. The row — not memory, not PubSub — is the source of truth.
2. **One job per unit of work** on a **dedicated Oban queue**; size total concurrency
   against the DB pool.
3. **Create the tracking row (`pending`) before enqueuing**; pass its id in the job args.
4. **Idempotency at both layers**: DB `on_conflict` upsert + Oban `unique`. Filter out
   already-done work before fan-out.
4b. **Batch the fan-out for large corpora**: one `Repo.insert_all` for the tracking
   rows + one `Oban.insert_all` for the jobs, not a per-unit `Oban.insert` loop — the
   loop's per-unit `NOTIFY` can wedge Oban's single notifier connection at scale (see
   §"Batch the enqueue itself" and `oban_production_diagnostics.md` §12). Prefer
   `Oban.Notifiers.PG` to remove that hazard at the root.
5. **Do I/O behind a config seam** (`:seed_file_fetcher`-style) so the worker is testable
   without network; **presign/mint short-lived credentials inside the job**, not before
   it queues.
6. **Worker returns `{:error, _}` for retryable failures** (let Oban retry); write a
   terminal `failed` status only for user-visible, exhausted failures. Make transition
   writes **tolerant of a missing row** (no-op, don't raise).
7. **LiveView enqueues via `start_async`**, subscribes **once** per scope, renders rows
   as a **`stream`** (O(1) patches).
8. **Two-tier broadcast**: full row on rare terminal transitions; identifiers-only signal
   on high-frequency intermediate ones. Ensure a terminal broadcast always follows, so
   dropped intermediate signals can't cause drift.
9. **Coalesce high-frequency signals** behind a flush timer to bound render rate.
10. **Keep shadow bookkeeping** (`file_index`, incremental `counts`) in assigns that
    don't re-render the stream, for merges and summaries.
11. **Reset cancels in-flight jobs before deleting rows**, scoped by queue + args.

## Source map

- `apps/mehungry_web/lib/mehungry_web/live/professional_live/S3BrowserLive.ex`
- `apps/mehungry/lib/mehungry/food_data/usda/seed_files.ex`
- `apps/mehungry/lib/mehungry/food_data/usda/seed_file.ex`
- `apps/mehungry/lib/mehungry/food_data/usda/seed_file_fetcher.ex`
- `apps/mehungry/lib/mehungry/oban_workers/seed_file_import_worker.ex`
- Queue config: `config/config.exs` (`seed_imports: 1`); test seam: `config/test.exs`
  (`:seed_file_fetcher`)
