# Measurement extraction — design review

A critical review of the full-text (PMC) + local-QA measurement-extraction feature as
it stands after the split into `apps/mehungry_local_ai`. Covers the **pros/cons of the
decisions made**, **model alternatives**, **next steps**, and **obstacles ahead**.

For *what it is / how to run it*, see `docs/measurement_extraction.md` and
`apps/mehungry_local_ai/README.md`. This document is the honest "here's what we bought
and what it will cost us" companion.

---

## 1. Scorecard of the decisions

### 1.1 Split extraction into a non-deployed local app over REST

**What:** the heavy Bumblebee/EXLA work runs off-box in `mehungry_local_ai`; the server
exposes `/api/local_ai/*` and keeps only data + review.

| Pros | Cons |
|---|---|
| Production release carries **zero** ML deps (`bumblebee`/`exla`/`nx`/`xla` — hundreds of MB, ~1–2 GB RAM). | Two moving parts + a shared secret to operate and keep in sync. |
| Heavy compute runs where the hardware is (GPU box), not on the 1 vCPU web/worker task. | Extraction is now **out-of-band**: no single "run" the server owns; progress is inferred from counts. |
| Clean seam — the local side is pure NLP + HTTP, easy to swap models without touching the server. | The API is an untyped, unversioned contract; client/server can drift. |
| Server stays the single source of truth (DB, review-gating). | Full-text fetch now happens from the GPU box → that box needs NCBI access + carries the rate-limit concern. |

**Verdict:** the right call for keeping prod lean and iterating on models independently.
The main debt is operational (secret, versioning, observability) — addressable.

### 1.2 In-umbrella app, excluded from Docker/release (vs a standalone repo)

| Pros | Cons |
|---|---|
| Shares config, code style, `mix.lock`; one repo to reason about. | Local `mix deps.get` / `mix compile` at the umbrella root still builds this app → the dev box needs EXLA/XLA even when you only want to touch the server. |
| Excluded cleanly: not in `releases:`, `Dockerfile` skips its `mix.*` and `rm -rf`s it. | The exclusion lives in the `Dockerfile` — a future change to that file (or a different build path, e.g. `mix release` run locally) can accidentally pull the ML tree back in. |
| No cross-repo version coordination. | Umbrella tooling (`mix test` from root) compiles the app, so CI that runs the whole umbrella still needs the ML deps unless scoped. |

**Verdict:** fine given a single Dockerfile build path. If a second build path appears,
promote the exclusion into something more robust than one `rm -rf` (e.g. a build profile,
or move to a standalone project).

### 1.3 PMC fetch moved into the local service (vs kept server-side)

| Pros | Cons |
|---|---|
| The local service is self-contained: PMID → text → candidates end-to-end. | Server no longer paces NCBI; the shared-budget rate limiter (`Mehungry.RateLimit`) was dropped for a fixed `Process.sleep`. If you also crawl (which hits NCBI) concurrently, the two can collide on NCBI's limits. |
| No large full-text bodies round-tripping server→client. | The GPU box needs outbound NCBI access + (ideally) an NCBI API key that currently isn't wired in on the local side. |
| Fetch and extract share one retry/skip loop. | Full text is re-fetched from scratch on each run for a study that failed to post — no local cache. |

**Verdict:** acceptable, but the NCBI-pacing story is now weaker than the server's was.
Wire an NCBI API key and a real token-bucket into `PMC.Client` before running at volume.

### 1.4 On-demand mix task (vs long-running poller / Oban)

| Pros | Cons |
|---|---|
| Dead simple; matches "run it at night" usage; nothing to supervise. | No durability: if the task dies mid-batch you lose in-flight progress (mitigated by idempotency, but the current study's fetch is wasted). |
| No always-on process, no queue to manage. | No backpressure/retry semantics beyond "skip and continue"; a flaky network just drops studies for this run. |
| Easy to reason about and to cron. | No live status back to the server while running (only end-of-run counts). |

**Verdict:** correct starting point. A poller/queue is a later optimization, not needed
until throughput matters.

### 1.5 Pure-NLP local / domain-on-server division

**What:** the extractor emits `{compound_id, value, unit, …}` findings; the server fans
each out across `species_ids_for_study/1` and upserts candidates.

| Pros | Cons |
|---|---|
| Local side knows nothing about species/DB — swappable and testable in isolation. | **Fan-out over-attribution:** one measurement is attributed to *every* species the study links to. A paper covering several foods can mint identical candidates against species it never measured. |
| Server owns the natural-key idempotency and review-gating. | The "which number belongs to which compound/food" decision is made by a weak heuristic upstream, then multiplied by fan-out downstream. |

**Verdict:** the layering is good; the **fan-out is the biggest correctness risk** in the
whole feature (see §4).

### 1.6 Shared bearer token auth

| Pros | Cons |
|---|---|
| Trivial to implement; constant-time compare; matches the Stripe-secret precedent. | Single static secret, no rotation, no per-client identity, no request signing. |
| No new infra. | Over plain HTTP (dev) it leaks; replay is possible (no nonce/timestamp). |

**Verdict:** fine for a single operator hitting HTTPS. Revisit if this ever becomes
multi-tenant or runs over untrusted networks (→ mTLS or HMAC-with-timestamp like Stripe).

### 1.7 The model + extraction method: extractive QA + regex

**What:** `distilbert-base-cased-distilled-squad` answers *"How much &lt;compound&gt; does
it contain?"* over 1400-char sliding windows; a regex (`@value_rx`) pulls `value+unit`
from the answer (or, in fallback, from spans within 160 chars of the compound name).

| Pros | Cons |
|---|---|
| Tiny (~65M params), CPU-friendly, free, offline, deterministic. | **Domain mismatch:** SQuAD is Wikipedia Q&A, not scientific composition tables. Recall/precision on results/tables is low. |
| Rule fallback keeps it working with the model off (tests/dev). | JATS tables are **flattened to prose** by the parser → the strongest signal (structured value/unit/prep columns) is destroyed before the model sees it. |
| Confidence score gives a cheap ranking signal. | SQuAD confidence is **not calibrated** for this task; the 0.4 rule score is arbitrary. |
| No API cost or rate limit. | Regex covers a narrow unit set; misses ranges (`3–5`), `±SD`, scientific notation, per-serving/DW/FW bases, and unicode unit variants. |
| | 200k-char cap truncates long papers — tables often sit at the end and get cut. |

**Verdict:** good enough to prove the pipeline end-to-end; **not** good enough for trustworthy
recall/precision. This is the highest-leverage thing to improve (see §2–§3).

---

## 2. Model alternatives (Hugging Face and beyond)

Bumblebee already loads Hugging Face models, so swapping is mostly a `MehungryLocalAi.QA`
change. Options, roughly in increasing capability/cost:

| Approach | Examples (HF) | Why | Trade-off |
|---|---|---|---|
| **Better extractive QA** | `deepset/roberta-base-squad2`, `deepset/tinyroberta-squad2` | Drop-in upgrade of the current path; better spans. | Same fundamental task mismatch; modest gains. |
| **Biomedical encoders (fine-tuned)** | `microsoft/BiomedNLP-PubMedBERT`, `dmis-lab/biobert`, `allenai/scibert_scivocab`, `michiyasunaga/BioLinkBERT` | Domain vocabulary; much better on scientific text if fine-tuned for QA or token-tagging. | Requires a **labeled dataset** + fine-tuning; no off-the-shelf measurement checkpoint. |
| **Measurement NER / token classification** | custom head on SciBERT; or non-NN tools **`grobid-quantities`**, **`quantulum3`** | Directly tags QUANTITY/UNIT (and normalizes units), which is what we actually want. | grobid-quantities is a Java service (integrate over HTTP, not Bumblebee); quantulum3 is Python. |
| **Table-structure extraction** | GROBID full-text TEI; parse JATS `<table-wrap>` directly (no model) | Composition data is tabular; keeping columns/headers is a bigger win than any model. | Parsing work, not ML; complements whatever model runs on prose. |
| **Local generative LLM w/ structured output** | `Qwen/Qwen2.5-7B-Instruct`, `meta-llama/Llama-3.1-8B-Instruct`, `microsoft/Phi-3.5` (via Bumblebee or Ollama/TGI) | Understands context; can return JSON `{compound, value, unit, prep, method, basis}` and resolve association. | Needs a real GPU; slower; **hallucination risk** → must keep review-gating + span citations. |
| **Hosted API (hybrid)** | Reuse `Mehungry.AI.Client` (Claude Haiku) for hard cases only | Highest quality per call; no local GPU. | Per-call cost + rate limits; defeats "fully local" for those calls — use as an opt-in fallback, not the default. |
| **Document/layout models** | Nougat, Donut (for PDFs) | If we ever ingest PDFs (non-OA), these recover structure. | Heavy; only relevant once we go beyond PMC XML. |

**Recommendation:** two parallel tracks — (a) **parse JATS tables structurally** (cheap,
big recall win, model-agnostic), and (b) trial a **local instruct LLM with JSON output**
for the prose path, benchmarked against the current QA model on a gold set. Keep the regex
path as the zero-dependency fallback.

---

## 3. Next steps (prioritized)

1. **Table-aware parsing.** Extract JATS `<table-wrap>`/`<table>` with headers and cells
   instead of flattening to prose. Most composition numbers live here. Biggest recall win.
2. **Build a gold benchmark.** ~50–100 hand-annotated (study, compound, value, unit,
   prep, method) tuples so any model/threshold change is measured, not guessed.
3. **Unit normalization + canonical basis.** Map `mg/100 g`, `mg/kg`, `%`, per-serving,
   DW vs FW to a canonical `(magnitude, unit, basis)`; reject/flag unconvertible ones.
4. **Fix compound↔quantity association.** Replace "nearest name within 160 chars" with a
   structure- or dependency-based link (or the LLM's own attribution), and **cite the
   exact span** for every candidate (already partly stored in `raw_span`).
5. **Constrain the species fan-out.** Attribute a measurement only to the species the
   *sentence/table* is about, not to every species linked to the paper (see §4).
6. **Capture mean ± SD, ranges, and sample size.** The schema already has `sample_size`;
   populate it and store dispersion so `EvidenceAggregation` can weight properly.
7. **NCBI hardening.** Wire an NCBI API key + a real token bucket into `PMC.Client`; add a
   small local cache so a re-run doesn't re-fetch.
8. **Run tracking + telemetry.** Optionally re-introduce a lightweight server-side "run"
   the endpoints bump (studies processed, candidates written, last-seen) so
   `/professional/science` shows live progress again, and errors are visible.
9. **API versioning + a typed contract.** Version the path (`/api/local_ai/v1/*`) and/or
   validate payloads (schema) so client/server drift is caught.
10. **Feedback loop.** Feed reviewer accept/reject back as labels to fine-tune or to tune
    the auto-vs-review threshold.
11. **Throughput.** Batch QA calls across compounds/chunks (currently one serving call per
    compound per chunk), and add a poller/queue mode when corpus size demands it.

---

## 4. Obstacles ahead

- **PMC open-access coverage is low.** Most PubMed papers aren't OA → fetched-but-empty;
  there is a hard recall ceiling no model can lift. Expanding beyond PMC (licensed
  full text, publisher APIs, PDFs) is a separate, larger project.
- **Precision from a mismatched model.** Until §2/§3 land, expect noisy candidates;
  review-gating is doing a lot of load-bearing work. Don't lower the review bar / raise
  auto-promotion until a benchmark says it's safe.
- **Association ambiguity is genuinely hard.** Papers list many compounds and many numbers
  in one paragraph/table; getting the right (compound, value) pair — and the right food —
  is the core scientific-NLP challenge, not a quick fix.
- **Fan-out over-attribution.** As shipped, a measurement is copied to every species the
  study links to. Combined with idempotent upserts, wrong attributions persist quietly.
  This is the correctness item to watch.
- **Truncation.** The 200k-char cap and sliding-window `max_chunks: 10` can silently drop
  the parts of long papers where tables live.
- **NCBI limits from a new origin.** Fetching from the GPU box (no shared budget, fixed
  sleep, no API key) risks throttling, especially if crawling runs at the same time.
- **Security surface.** Static bearer token, no rotation, replay-able; must stay on HTTPS.
  A leaked token lets anyone write candidates (still review-gated, but noisy).
- **Contract drift.** No versioning/validation on `/api/local_ai/*`; a change on one side
  can break the other with a runtime error rather than a clear failure.
- **Reproducibility of the local model.** Model version, EXLA/XLA platform, and cache
  location aren't pinned; results can shift silently across machines/upgrades.
- **Operational drift.** Because extraction is off-box and on-demand, "did anyone run it
  lately?" has no server-side answer today (until §3.8). Easy for the queue of unreviewed
  candidates to go stale.

---

## 5. Bottom line

The **architecture** is sound: prod stays lean, the heavy work is isolated and swappable,
and the safety model (facts only via human review) is intact. The **weak link is the
science**, not the plumbing — extractive QA over flattened text with a proximity
heuristic and a static fan-out. The highest-value work is therefore **not** a bigger model
first, but **table-aware parsing + a gold benchmark + tighter association/attribution**,
with a local instruct LLM (Hugging Face, via Bumblebee) as a strong candidate for the
prose path once there's a benchmark to prove it out.
