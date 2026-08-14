# mehungry_local_ai

A **local-only, non-deployed** umbrella app that does the GPU/CPU-heavy part of the
science pipeline — fetching scientific full text and running a local
extractive-QA model over it to pull **quantitative compound measurements**
(`compound = value unit`) — and pushes the results back to the deployed Mehungry
server over a small REST API.

It exists so the production release stays lean: **no `bumblebee` / `exla` / `nx` /
`xla`** dependencies ship to the server. You run this app on a machine with real
hardware (a GPU box or a beefy laptop), point it at production (or your local dev
server), and it becomes a batch worker for measurement extraction.

> TL;DR
> ```bash
> export LOCAL_AI_SERVER_URL="https://your-mehungry-host"   # or http://localhost:4000
> export LOCAL_AI_API_TOKEN="the-shared-secret"             # must match the server
> mix local_ai.extract --limit 200
> ```

---

## 1. Where it sits in the science pipeline

The full science pipeline (see `docs/science/scientific_pipeline.md`) runs on the server in
ordered stages. Measurement extraction is the **last discovery stage**, and it is the
only one that runs **off-box** in this app:

```
                          ┌─────────────────────── SERVER (deployed) ───────────────────────┐
 USDA Schema curation ─▶  │  FoundementalFoodSpecies (name + scientific_name + ingredients)  │
 (/professional/usda-schema)                                                                  │
                          │                                                                   │
 1) Literature crawl   ─▶ │  Entrez/PubMed → ScientificStudy (pmid) ── StudyIngredient links  │
    (imports queue)       │                                                                   │
 2) PubTator annotation ▶ │  ScientificStudy → StudyEntityMention (chemicals → compound_id)   │
    (imports queue)       │                                                                   │
                          │                                                                   │
 3) MEASUREMENT EXTRACTION│  ── served as "pending" ──▶  ┌──────────────────────────────┐     │
    (THIS APP, off-box)   │  ◀── full text + candidates ─┤  mehungry_local_ai (GPU box) │     │
                          │                              └──────────────────────────────┘     │
                          │                                                                   │
 4) Candidate review   ─▶ │  /professional/compound-candidates → Accept → CompoundMeasurement │
                          └───────────────────────────────────────────────────────────────────┘
```

### What must already be true before this app finds work

A study is only *useful* to extract from when the upstream stages have populated:

- **`pmid`** on the `ScientificStudy` — produced by the **literature crawl** (stage 1).
  This app resolves the PMID to a PMCID and fetches PMC open-access full text.
- **Compound mentions** — `StudyEntityMention` rows with a resolved `compound_id`,
  produced by **PubTator annotation** (stage 2). The server sends these compounds
  (name + synonyms) alongside each study; the extractor asks "how much of *this*
  compound?" and scans for its name. **No compounds ⇒ no candidates** (the full text
  is still fetched and stored, but nothing is extracted).
- **Species links** — `StudyIngredient` → `FoundementalFood` → `FoundementalFoodSpecies`,
  established by curating ingredients onto a species in the **USDA Schema** view. The
  server uses these to fan each finding out to the implicated species when it stores a
  candidate. **No species links ⇒ candidates can't be attached** (nothing is written).

So the practical order of operations is: **crawl → annotate → (curate species) →
run this app → review**. If you run this app before crawl/annotation, `pending` will be
empty or the studies will have no compounds.

### What happens after this app posts

Every finding is stored server-side as a **review-gated** `CompoundMeasurementCandidate`
(status `pending`) — never a fact. A human reviews them at
**`/professional/compound-candidates`**:

- **Accept** materializes an immutable `CompoundMeasurement` against a representative
  curated ingredient of the species (`Food.record_measurement/1`).
- **Reject** drops the candidate.

The read-only **`/professional/science`** "Full-text extraction" panel shows how many
PMID-bearing studies still lack a fetch attempt, and how many candidates are pending
review — that's your at-a-glance progress while this app runs.

---

## 2. What the app does, step by step

`mix local_ai.extract` runs this loop until it has processed `--limit` studies (or the
server has no more pending work):

1. **`GET /api/local_ai/pending`** → a batch of studies needing processing, each with
   its `pmid` and the compounds to look for: `{study_id, pmid, compounds:[{id,name,synonyms}]}`.
2. For each study, **`MehungryLocalAi.PMC.fetch(pmid)`**:
   - resolve PMID → PMCID via the NCBI id-converter,
   - `efetch db=pmc` for the JATS XML,
   - strip JATS → plain text.
   - Outcome is one of `open_access` (got body), `no_pmcid`, `not_oa`, or `error`.
3. **`POST /api/local_ai/full_text`** with `{study_id, pmcid, source, body, outcome}`.
   The server stores the body (when present) and **always ledgers the fetch attempt**,
   which removes the study from `pending` — this is what makes the batch terminate.
4. If open-access, **`MehungryLocalAi.Extractor.findings(text, compounds)`**:
   - **QA-primary** (when the model is loaded): ask
     *"How much &lt;compound&gt; does it contain?"* over sliding windows of the text and
     parse a `value + unit` out of the best-scoring answer span; the model's confidence
     is the score.
   - **Rule-based fallback** (when the model is off — e.g. tests): find `number + unit`
     spans (`mg/100 g`, `%`, …) near the compound name; fixed score `0.4`.
5. **`POST /api/local_ai/candidates`** with the findings (each tagged `study_id` +
   `compound_id`). The server fans each finding across the study's species and upserts
   idempotent candidates.

Nothing here touches a database. The app is pure NLP + HTTP; all domain knowledge
(which species, how to persist) lives on the server.

---

## 3. Prerequisites

- The umbrella's toolchain (Elixir/Erlang per the repo's `.tool-versions` / Dockerfile —
  Elixir 1.16+).
- `mix deps.get` at the **umbrella root** — this fetches `bumblebee`, `exla`, `nx`,
  `xla` (a few hundred MB; `xla` downloads a prebuilt binary). These are declared only
  in this app's `mix.exs`, so they land in the shared `deps/` for local builds and are
  **never** fetched by the production Docker build.
- Enough RAM for the QA model (~1–2 GB while running).
- Network access to **NCBI** (idconv + E-utilities) and to your **Mehungry server**.
- **First run downloads the model** (`distilbert-base-cased-distilled-squad`) from
  Hugging Face into the Bumblebee cache (`~/.cache/bumblebee`, override with
  `BUMBLEBEE_CACHE_DIR`). Subsequent runs reuse it. EXLA also compiles kernels on first
  use, so the first `mix local_ai.extract` is slow to start.

---

## 4. Configuration

Two sides share **one secret**.

### On the server (deployed `mehungry_web`)

Set the shared bearer token the API guard checks:

| Env var | Config key | Purpose |
|---|---|---|
| `LOCAL_AI_API_TOKEN` | `:mehungry, :local_ai_api_token` | Secret the `/api/local_ai/*` guard compares against (constant-time). If unset, the API returns **500** and rejects everything. |

(Read in `config/runtime.exs`; only overrides the compile-time value when the env var
is actually present, so dev/test keep their defaults.)

### On this app (the GPU box)

| Env var | Config key | Default | Purpose |
|---|---|---|---|
| `LOCAL_AI_SERVER_URL` | `:mehungry_local_ai, :server_base_url` | `http://localhost:4000` | Base URL of the Mehungry server to pull from / post to. |
| `LOCAL_AI_API_TOKEN` | `:mehungry_local_ai, :api_token` | *(none)* | Bearer token — **must equal the server's** `LOCAL_AI_API_TOKEN`. |
| *(none)* | `:mehungry_local_ai, :start_qa` | `false` | Whether to **auto-load** the Bumblebee model at app boot. Off by default so the umbrella/dev/tests never download or compile the model; `mix local_ai.extract` loads it on demand via `MehungryLocalAi.QA.ensure_started/0` regardless. Set `true` only on a dedicated GPU box that should have the serving up at boot. |
| *(none)* | `:mehungry_local_ai, :pmc_http_adapter` | `&HTTPoison.get/3` | HTTP seam for NCBI calls; stubbed in tests. |

Example:

```bash
export LOCAL_AI_SERVER_URL="https://mehungry.example.com"
export LOCAL_AI_API_TOKEN="$(cat ~/.mehungry_local_ai_token)"
```

Generate a token once (any high-entropy string) and put the same value in both places:

```bash
openssl rand -hex 32
```

---

## 5. Running

From the **umbrella root**:

```bash
# Process up to 200 studies, then exit.
mix local_ai.extract --limit 200

# Smaller batch (e.g. a quick smoke run).
mix local_ai.extract --limit 5
```

Options:

- `--limit N` — total studies to process this run (default `100`). The app pulls in
  internal batches of 25 and stops once it has handled `N` (or `pending` is empty).
- `--offset M` — starting offset (default `0`). Note: because posting a fetch result
  removes a study from `pending`, the set naturally advances; `--offset` is accepted for
  forward-compatibility but is currently a no-op server-side.
- `--no-qa` — skip loading the Bumblebee model and run the rule-based extractor only.
  The QA serving is otherwise loaded once at the start of the run (slow on first run —
  downloads the model), since it does not auto-start at app boot.

Typical output:

```
local_ai.extract: processing up to 200 studies (QA available? true)
done: processed 200 studies, stored 41 full texts, posted 63 candidates
```

`stored full texts` counts open-access papers whose body was saved; most papers aren't
OA and are recorded as a skip (`no_pmcid` / `not_oa`). `posted candidates` is the total
number of measurement candidates the server wrote (after fanning out across species).

### Nightly use

There's no long-running process — run it on demand (e.g. a nightly cron on the GPU box):

```cron
0 2 * * *  cd /path/to/mehungry_umbrella && LOCAL_AI_SERVER_URL=... LOCAL_AI_API_TOKEN=... mix local_ai.extract --limit 500 >> /var/log/local_ai_extract.log 2>&1
```

Re-running is safe: candidate upserts are idempotent on their natural key, and studies
already fetched won't reappear in `pending`.

---

## 6. REST API contract

All routes are under `scope "/api/local_ai"` in the server router, behind the
`:local_ai_api` pipeline (`accepts json` + `RequireLocalAiToken`). Every request needs
`Authorization: Bearer <LOCAL_AI_API_TOKEN>`; a missing/wrong token → **401**, an
unconfigured server secret → **500**.

### `GET /api/local_ai/pending?limit=N`
Studies with a `pmid` and no PMC fetch attempt yet, each with the compounds to look for.
```json
{
  "studies": [
    {
      "study_id": 123,
      "pmid": 45678,
      "compounds": [
        { "id": 7, "name": "L-Ascorbic Acid", "synonyms": ["ascorbic acid"] }
      ]
    }
  ],
  "total": 512
}
```
`total` is an estimate of remaining unfetched studies (for progress display).

### `POST /api/local_ai/full_text`
Store the fetched body (when open-access) and ledger the attempt so the study leaves
`pending`.
```json
{ "study_id": 123, "pmcid": "PMC42", "source": "pmc_oa",
  "body": "Results: ... 260 mg/100 g ...", "outcome": "open_access" }
```
→ `{ "ok": true }`. `body`/`pmcid` may be omitted for a skip; `outcome` ∈
`open_access | no_pmcid | not_oa | error`.

### `POST /api/local_ai/candidates`
Persist findings; the server fans each one across `species_ids_for_study/1` and upserts.
```json
{ "candidates": [
  { "study_id": 123, "compound_id": 7, "value": 260.0, "unit": "mg/100 g",
    "preparation_method": "raw", "analytical_method": "HPLC",
    "score": 0.87, "raw_span": "…260 mg/100 g…", "extraction_method": "automated" }
]}
```
→ `{ "written": 1 }` (number of candidate rows written across all species).

---

## 7. Module map

| Module | Role |
|---|---|
| `Mix.Tasks.LocalAi.Extract` | CLI entry point; boots the app + drives the pull → fetch → extract → push loop. |
| `MehungryLocalAi.Application` | Supervises `MehungryLocalAi.QA`. |
| `MehungryLocalAi.QA` | Bumblebee extractive-QA `Nx.Serving` (`distilbert-squad`, `compiler: EXLA`). Not started at boot unless `:start_qa` is `true`; `ensure_started/0` loads it on demand (used by `mix local_ai.extract`). |
| `MehungryLocalAi.PMC` | Orchestrates one study's fetch: resolve PMCID → efetch → parse → outcome. |
| `MehungryLocalAi.PMC.Client` | NCBI HTTP (idconv + `efetch db=pmc`), with a `Process.sleep` pace and the `:pmc_http_adapter` seam. |
| `MehungryLocalAi.PMC.Parser` | JATS XML → plain text (regex tag-strip + entity decode, capped at 200k chars). |
| `MehungryLocalAi.Extractor` | `findings(text, compounds)` → finding maps. QA-primary, rule fallback. |
| `MehungryLocalAi.Client` | HTTP client for the three server endpoints (bearer auth, JSON). |

Server side (in `apps/mehungry_web`): `MehungryWeb.Plugs.RequireLocalAiToken` +
`MehungryWeb.Api.LocalAi.{PendingController, FullTextController, CandidatesController}`,
reusing `Mehungry.Literature` and `Mehungry.Food` functions.

---

## 8. Why it isn't deployed

- It's **not** in the release: the umbrella root `mix.exs` `releases:` block lists only
  `mehungry` and `mehungry_web`.
- The `Dockerfile` copies only the two deployable apps' `mix.*` before
  `mix deps.get --only prod` (so `bumblebee`/`exla`/`xla` are never fetched in prod) and
  then `rm -rf apps/mehungry_local_ai` before building the release (so the umbrella
  compile never touches it).

Result: production carries none of the ML dependency weight; this app is a developer/
operator tool you run yourself against the live REST API.

---

## 9. Tests

```bash
mix cmd --app mehungry_local_ai mix test
```

Tests run with `:start_qa` off, so the model is never downloaded — the extractor is
exercised via its rule-based path and PMC via a stubbed HTTP adapter. The server-side
REST endpoints are tested in
`apps/mehungry_web/test/mehungry_web/controllers/api/local_ai_test.exs`.

---

## 10. Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `pending` returns `[]` | No un-fetched studies. Run the **crawl** (stage 1) on the server first, or everything has already been fetched. |
| Studies come back with empty `compounds` | **PubTator annotation** (stage 2) hasn't linked chemicals yet. Full text is still fetched, but nothing is extracted. |
| `stored full texts` is 0 | Normal — most PubMed papers aren't PMC open-access (`no_pmcid` / `not_oa`). |
| Candidates posted but none appear for review | The studies have no **species links**. Curate ingredients onto a `FoundementalFoodSpecies` in `/professional/usda-schema`. `written` will be 0 when a study has no species. |
| `401` on every call | Token mismatch — `LOCAL_AI_API_TOKEN` here must equal the server's. |
| `500 {"error":"local_ai_api_token not configured"}` | The server has no `LOCAL_AI_API_TOKEN` set. |
| First run hangs at startup | Model download + EXLA compile. Let it finish once; it's cached afterwards. Set `BUMBLEBEE_CACHE_DIR` to control the location. |
| `pending fetch failed … — stopping` | Server URL/network/token problem; the loop exits gracefully. Check `LOCAL_AI_SERVER_URL`. |
| Frequent `rate_limited` on NCBI | The client already paces requests; set an NCBI API key upstream or lower `--limit` if you're also crawling at the same time. |

See also: `docs/ai/measurement_extraction.md` (the split + endpoint reference) and
`docs/science/scientific_pipeline.md` (the whole discover → curate → advise flow).
