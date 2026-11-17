# Memory management strategy

**Status:** strategy + measurement tooling landed 2026-11-16. The two behaviour-changing
safeguards (§6.1 boot caps, §6.2 request-path gating) are **specified and ready but not yet
wired** — see §9.

This is the clear, end-to-end answer to: *how do we measure memory, how do we enforce limits,
how do we get the machine's limit into the app, and what do we do about the C-level graphics
library — so we can be certain?*

---

## 1. The one idea that removes the uncertainty

**Elixir memory is not one number — it is three domains, and the dashboards only show one of them.**

| Domain | What it is | Measured by | GC'd? |
|---|---|---|---|
| **1. BEAM heap** | process heaps, refc **binary** heap, ETS, atoms, code | `:erlang.memory/0`, LiveDashboard, PromEx, BeamScope | yes (per-process copying GC; binaries ref-counted) |
| **2. Native / NIF** | libvips decode buffers + its **100 MB operation cache** + its **thread pool**; bcrypt buffers; any Rust/C allocation | **nothing in-app** — invisible to `:erlang.memory/0` | no — managed by the C library itself |
| **3. OS / cgroup (RSS)** | the physical pages Fly counts against the **1 GB** limit; what the **OOM killer** acts on | `/proc/self/status` `VmRSS`, cgroup `memory.current` | n/a |

`RSS  ≈  BEAM_total  +  native_footprint  +  code/stack/fragmentation`

The historical "memory uncertainty" is exactly this: **every tool we had watched Domain 1, while
the thing that OOM-kills us lives in Domain 2 and is only visible in Domain 3.** A measured example
from this repo's image pipeline (`mix mem.probe`, synthetic 6000×6000 source, dev box):

```
baseline     BEAM 72 MB | RSS 256 MB | native(RSS-BEAM) 183 MB   ← 70% of RSS is invisible to BEAM
iter 1       peak-RSS 308 MB                                     ← single cold render, BEAM still 72 MB
after 25×    settled-RSS ~185 MB (capped) … ~291 MB (defaults)
```

BEAM sat **flat at ~72 MB** the entire time while RSS swung by **>110 MB**. If you only watched
`:erlang.memory` you'd conclude the app was idle. **Rule: for this app, "memory" means RSS, not
BEAM total. Always measure the gap.**

---

## 2. How we measure (the instrument)

Ship and keep `mix mem.probe` (`apps/mehungry_web/lib/mix/tasks/mem.probe.ex`). It samples all
three domains at once, including the **transient peak** (a background sampler reads RSS every 3 ms,
so we catch a decode spike that a point-in-time read would miss).

```bash
# locally (dev build, no DB needed — exercises only vix):
mix mem.probe
mix mem.probe --iterations 40 --cap --concurrency 2

# on the real machine, where the cgroup limit is the actual ceiling:
fly ssh console -C "/app/bin/mehungry_umbrella eval 'Mix.Tasks.Mem.Probe.run([])'"
```

The reusable primitives in that task are the measurement contract:

- `Mix.Tasks.Mem.Probe.rss_bytes/0` — **Domain 3 for this process** (`VmRSS`).
- `Mix.Tasks.Mem.Probe.cgroup_limit/0` — the machine's **real limit + current usage**, read from
  cgroup v2 (`/sys/fs/cgroup/memory.max` / `memory.current`) then v1. This is §4.
- `:erlang.memory/0` — **Domain 1**. `:binary` is the refc-binary heap (image binaries live here).
- `native = RSS − BEAM_total` — the **Domain 2 proxy**. (libvips' own `vips_tracked_get_mem` is
  not bound in vix 0.23.1, so the RSS-minus-BEAM gap is the honest native number — and it's the one
  the OOM killer agrees with anyway.)

**Leak vs. peak diagnosis** (what the probe tells you apart):
- `after + GC` RSS returns to ~baseline  → clean; your risk is **peak × concurrency** (§6).
- `after + GC` RSS climbs run over run    → a **native leak** (a Vix image/binary ref pinned by a
  long-lived process, or libvips cache growth) — chase it with `--iterations 200`.

Continuous visibility (so we never fly blind again): add a periodic telemetry gauge that emits
**RSS and the RSS−BEAM gap**, not just BEAM metrics, so PromEx/Grafana and `/beam_scope` show the
number that actually moves. (Cheap: one `:telemetry.execute` from a poller reading `rss_bytes/0`.)

---

## 3. Why the graphics pipeline is the whole story

`:vix`/`:image` wrap **libvips** (C/C++, with bundled librsvg/pango/cairo for the SVG overlays).
It is the **only** off-heap-heavy dependency that ships in production. Full map in the agent recon;
the load-bearing facts:

- **Heaviest path:** `MehungryWeb.InsightGraphic` — `Image.open(body)` (full decode of a recipe
  photo of *arbitrary* resolution) → `thumbnail` 1080² → `flatten` → `from_svg` (rasterise a full
  1080² overlay) → `compose` → `write(:memory)`. The source JPEG binary is **pinned in the BEAM
  process for the whole `with` chain**, the libvips intermediates live in Domain 2, and the output
  JPEG is then **held across a 30 s Storage HTTP upload**.
- **Default libvips config, unoverridden:** `cache_max_mem = 100 MB`, `cache_max = 100 ops`,
  `concurrency = CPU count` (16 on a dev box; ~2 on `shared-cpu-1x`). On a 1 GB machine that 100 MB
  cache is **10% of RAM** sitting in Domain 2, and each worker thread carries decode buffers.
- **Concurrency is only half-bounded.** Background renders run on Oban `:ai_agents` (limit **1**) —
  good. But two surfaces run libvips **off that queue**:
  - `recipe_details_component.ex` renders the insight graphic in a `start_async` **linked to the
    LiveView** → bounded only by concurrent users (HTTP `soft_limit` 200 / `hard_limit` 250).
  - `search_live` calls `ImageProcessing.resize/4` **synchronously in the LiveView**, after writing
    the full remote body to disk.
  Peak native memory = (concurrent libvips ops) × (per-op working set). Unbounded concurrency on a
  1 GB box is the OOM path, and the 512 MB swap cushion in `fly.toml` is the only thing currently
  absorbing it.

Other natives are non-issues: **bcrypt** (tiny fixed buffers, dirty-NIF, CPU-bound not RAM-bound);
the **ML stack** (`exla`/`nx`/`bumblebee`/XLA — would arena-allocate huge native tensors, but is
**excluded from the deployed image**, living only in the non-deployed `apps/mehungry_local_ai`).

---

## 4. Getting the machine limit into the app layer

The machine's RAM ceiling is **not** a magic global the app knows. Transfer it explicitly:

1. **Source of truth = the cgroup**, not `free`/`:memsup`. `:os_mon` is started
   (`apps/mehungry_web/mix.exs`) but **unused**, and on a container `:memsup` reports the *host's*
   memory, not the machine's slice — a classic trap. Read the cgroup instead:
   `Mix.Tasks.Mem.Probe.cgroup_limit/0` returns `memory.max` + `memory.current`.
2. **Derive a native budget at boot** from that limit and feed it to Domain 2:
   `budget_for_libvips = cgroup_limit − (headroom for BEAM + web + Presence + DB pool)`.
   On a 1 GB machine with 2 nodes, a safe shape is ≈ BEAM/web ~350 MB, libvips cache **0** (the
   cache buys little for one-shot renders — see §6.1), threads **2**, leaving swap purely as a
   cushion rather than a working surface.
3. **Hand it to the one knob that matters:** `MehungryWeb.VipsMemory.configure/0` sets
   `cache_set_max_mem`, `cache_set_max`, `concurrency_set`. There is **no global BEAM heap cap** in
   the ERTS model — you bound Domain 1 per-process (`max_heap_size`, §6.3) and bound Domain 2 at the
   library. The cgroup limit flows: **cgroup → boot budget → VipsMemory + max_heap_size + Oban
   limits.**

---

## 5. How we enforce limits — ranked by leverage

1. **Bound concurrency of native work (biggest lever).** Peak native RSS is linear in concurrent
   libvips ops. Keep background renders at Oban `:ai_agents` = 1; **put the request-path renders
   behind a bounded concurrency gate** (§6.2) so N users can't launch N simultaneous decodes.
2. **Cap the libvips cache + thread pool at boot** (§6.1) — `VipsMemory.configure/0`. Removes the
   100 MB standing cache and bounds per-thread working buffers. **Must run before the first render**
   (the thread pool is created lazily and can't be shrunk after).
3. **Decode at bounded resolution.** Prefer `Image.thumbnail(path, …)` (libvips **shrink-on-load**:
   decodes straight to target size) over `Image.open` + `thumbnail` (full decode first). Cap input
   dimensions before `open/1` for arbitrary user photos.
4. **Don't pin big binaries across slow I/O.** The output JPEG is held across the 30 s Storage
   upload; do the native work in a **short-lived process that then dies** (dying frees the refc
   binary ref immediately) rather than a long-lived worker, and `:erlang.garbage_collect/0` after
   holding a large binary.
5. **Per-process `max_heap_size`** (§6.3) — kills a runaway BEAM process (Domain 1) before it takes
   the machine, turning an OOM-kill-the-node into a crash-one-process.
6. **Swap = last-resort cushion, not a strategy.** The existing 512 MB stays; it should rarely be
   touched once 1–4 are in place.

---

## 6. The concrete safeguards

### 6.1 Cap libvips at boot — `MehungryWeb.VipsMemory` *(ready, not wired)*
Add to `MehungryWeb.Application.start/2`, **before `MehungryWeb.Endpoint`**:
```elixir
MehungryWeb.VipsMemory.configure()
children = [ MehungryWeb.PromEx, MehungryWeb.Presence, MehungryWeb.Telemetry,
             MehungryWeb.Endpoint, ... ]
```
Defaults: cache 0 MB / 0 ops, concurrency 2. Override per environment via
`config :mehungry_web, MehungryWeb.VipsMemory, concurrency: …`. Measured effect vs. defaults when
applied at boot: **settled native ~102 MB → ~75 MB, first-render peak 269 MB → 181 MB (−33%).**

### 6.2 Gate the request-path renders *(specified, not wired)*
The `start_async` insight render and the synchronous `ImageProcessing.resize` must not scale with
user count. Options, cheapest first:
- Route both through a **bounded `Task.Supervisor` + a counting semaphore** (e.g. max 2 concurrent
  libvips ops process-wide), rejecting/queueing past the cap.
- Or move the on-request insight render to the **`:ai_agents` Oban queue** it already has a worker
  for (`RecipeSocialGraphicWorker`) and have the LiveView subscribe to the PubSub result — unifying
  both trigger surfaces on the single-slot queue.

### 6.3 Per-process heap ceiling *(config, not wired)*
Set a spawn/`max_heap_size` ceiling on the image task processes (and consider a global
`+hmax`/`ERL_FULLSWEEP_AFTER` in `rel/vm.args.eex`, currently all commented out) so one pathological
decode kills its own process instead of the node.

---

## 7. Adding a new C-level dependency — the checklist

Every native dep manages memory differently, so vet each against Domain 2 **before** adding it:

1. **Does it allocate off the BEAM heap?** (NIF/Rust/C → yes; pure Elixir/Erlang → no, skip the
   rest.) If yes, `:erlang.memory` will not see it — plan to measure via RSS.
2. **Does it keep its own cache or pool?** (libvips: 100 MB cache + threadpool; XLA: device
   arenas; tokenizers: bounded per-call.) If yes, find the knob to cap it **at boot** and read
   `docs` for the default — assume the default is tuned for a big box, not a 1 GB machine.
3. **What's the peak per call, and is it bounded by input size?** Decode/tensor libs scale with
   *dimensions*, not file size. Cap or validate inputs.
4. **Prove it with `mix mem.probe` before merging** — add a pass that exercises the new dep and
   confirm settled RSS returns to baseline (no leak) and peak × intended-concurrency fits the
   budget from §4.
5. **Bound its concurrency** (dedicated Oban queue with `limit:` and/or a semaphore). Default to 1
   until measured.
6. **Confirm it's actually in the release** (or deliberately excluded, like the ML stack) — a dep
   in `mix.lock` isn't necessarily in the deployed image.

A native dep that fails 2–5 and can't be bounded belongs in a **separate, non-deployed service**
(the pattern already used for `apps/mehungry_local_ai`), reached over HTTP — not in the 1 GB web
machine.

---

## 8. What is already true (baseline, 2026-11-16)

- 2× `shared-cpu-1x` / **1 GB** + **512 MB swap** each (`fly.toml`); `min_machines_running = 2`.
- `ERL_AFLAGS = "+S 2:2 +sbwt none …"` (schedulers only). **No ERTS allocator/heap flags**
  anywhere; `rel/*vm.args.eex` memory flags all commented out.
- Oban total **15 slots**; image/graphic work on `:ai_agents` **limit 1** (background only).
- libvips at **defaults** (100 MB cache, CPU-count threads) — unoverridden.
- `:os_mon` started but **unused**; **no** RSS probe, memory watchdog, or OOM guard exists. Only
  stock BEAM-heap metrics (PromEx/LiveDashboard/BeamScope) — i.e. Domain 1 only.

## 9. Open items (the wiring)

- [ ] Wire `MehungryWeb.VipsMemory.configure/0` into `Application.start/2` (§6.1).
- [ ] Gate the two request-path libvips surfaces (§6.2).
- [ ] Emit an RSS + RSS−BEAM telemetry gauge so Grafana/BeamScope show Domain 3 (§2).
- [ ] Set per-process `max_heap_size` on image tasks (§6.3).
- [ ] Run `mix mem.probe` **on the Fly machine** to capture real cgroup-bounded numbers (dev box
      has no cgroup cap, so local peaks are not the production ceiling).
