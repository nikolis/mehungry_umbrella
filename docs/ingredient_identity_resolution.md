# Ingredient Scientific Identity Resolution

A decoupled enrichment layer that maps existing **USDA-backed ingredients** to
**external scientific identifiers** — scientific (binomial) name, NCBI Taxonomy ID,
FoodOn ID, Wikidata ID, and synonyms — as *candidate* mappings with confidence
scores, provenance, and a manual verification workflow.

> Example: the ingredient `"Spinach, raw"` resolves to `Spinacia oleracea`
> (NCBI `3562`, FoodOn `FOODON:00003278`, Wikidata `Q37937`).

It never modifies the USDA ingestion pipeline or any existing table. All writes are
append-only and history-preserving.

---

## 1. Why this exists

The `ingredients` table is USDA-centric: `fdc_id`, `ndb_number`, nutrients, portions.
It has no link to the wider scientific data ecosystem (taxonomy databases, ontologies,
Wikidata). This layer bridges that gap so ingredients can be:

- deduplicated/aligned across data sources by a stable scientific identity;
- joined to ontology-driven data (FoodOn) and taxonomy trees (NCBI);
- enriched with synonyms for better search and matching.

**Constraints honored:**

- New Ecto schemas + migrations only — no existing table is altered.
- USDA ingestion (`FoodParser`, `FdcClient`, reconciliation worker) is untouched.
- Multiple candidate identities per ingredient; each with confidence + provenance.
- **Never overwrites** an existing mapping; **preserves history**.
- Manual verification workflow.
- Runs as an Oban pipeline with **retries** and **progress tracking**, mirroring the
  existing seeding (`seed_files`) / taxonomy-classification (`taxonomy_classification_runs`)
  patterns.

---

## 2. Data model

Four new tables (migration
`priv/repo/migrations/20260725140000_create_ingredient_scientific_identities.exs`).
All are keyed by `ingredient_id` and never read/written by ingestion.

```
                         ┌─────────────────────────────────────────────┐
   ingredients ─────────<│ ingredient_scientific_identities            │
   (existing, USDA)       │  scientific_name, rank                      │
        │  id             │  ncbi_taxonomy_id, foodon_id, wikidata_id   │
        │                 │  source, id_source, confidence              │
        │                 │  status: candidate|verified|rejected|super. │
        │                 │  verified_by_user_id, verified_at           │
        │                 │  superseded_by_id ──┐ (self, history chain)  │
        │                 └─────────┬───────────┴──────────────┬────────┘
        │                           │ id                       │ enrichment_source_id
        │                           │                          v
        │             ┌─────────────┴──────────┐   ingredient_enrichment_sources
        │             │ ingredient_identity_    │   (reused citation registry)
        │             │ synonyms                │
        │             │  name, synonym_type,    │
        │             │  language_name, source  │
        │             └────────────────────────┘
        │
        ├──< ingredient_identity_resolution_attempts   (per-ingredient ledger)
        │       source, outcome (matched|no_scientific_name|error), detail
        │
   (global) ingredient_identity_resolution_runs        (aggregate progress)
              status, resolved, total, started_at, completed_at
```

### `ingredient_scientific_identities` — candidate identities
The core table. **Append-only**: rows are never updated to change their scientific
content; new evidence is a new row. Key columns:

| Column | Meaning |
|---|---|
| `scientific_name` | Binomial name (from USDA `scientificName`). Required. |
| `rank` | Taxonomic rank (species/genus…), when known. |
| `ncbi_taxonomy_id` | NCBI Taxonomy ID (the "taxonomy_id" in the request). |
| `foodon_id` | FoodOn ontology id, e.g. `FOODON:00003278`. |
| `wikidata_id` | Wikidata Q-id, e.g. `Q37937`. |
| `source` | Provenance of the *name*: `usda_fdc \| manual \| ai \| external_db`. |
| `id_source` | Provenance of the *external ids*: `wikidata \| ncbi \| foodon \| ols \| manual`. |
| `confidence` | 0.0–1.0 score. USDA-derived names default to `0.9`. |
| `status` | `candidate \| verified \| rejected \| superseded`. |
| `verified_by_user_id`, `verified_at` | Manual verification audit. |
| `superseded_by_id` | Self-FK: the identity that replaced this one (history chain). |
| `enrichment_source_id` | Optional citation into `ingredient_enrichment_sources`. |

**Indexes / guarantees:**
- `unique (ingredient_id, scientific_name, source)` — makes writes a find-or-create; re-resolution never duplicates or overwrites.
- **Partial** `unique (ingredient_id) where status = 'verified'` (`one_verified_identity_per_ingredient`) — at most one verified identity per ingredient, enforced by the DB.

### `ingredient_identity_synonyms` — synonyms, per identity
Synonyms belong to a specific identity (a taxon's synonyms), so provenance stays
tight. An ingredient's full synonym list is a join across its identities
(`list_synonyms_for_ingredient/1`). `unique (scientific_identity_id, name, synonym_type)`.

### `ingredient_identity_resolution_attempts` — per-item ledger
Mirrors the role of `seed_files`: records that an ingredient was processed for a
given `source` (`usda_fdc`) with an `outcome`, even when no name was found. This is
what lets the batch worker **terminate** (already-attempted ingredients are excluded)
and provides an audit trail. `unique (ingredient_id, source)` (upsertable — it is
process metadata, not a mapping).

### `ingredient_identity_resolution_runs` — aggregate progress
Mirrors `taxonomy_classification_runs`: one row per resolution pass with a
`resolved / total` coverage snapshot and a `pending → processing → completed | failed`
status. Every transition is broadcast on PubSub for live progress UIs.

---

## 3. How resolution works

### 3.1 The USDA leverage (using more of the USDA API)

The USDA FDC detail endpoint `/food/{fdcId}` returns a top-level **`scientificName`**
for Foundation and SR-Legacy foods. Our ingestion adapter
(`FdcClient.to_parser_format/1`) deliberately **drops** it because ingestion doesn't
need it.

`Mehungry.Food.IdentityResolution.UsdaScientificSource` harvests it *additively*:
it re-fetches `/food/{fdcId}` through the existing shared HTTP layer
`Mehungry.FoodData.Usda.FdcHttp.get/1` (which already provides retries, the
`x-ratelimit-remaining` header, and `{:error, {:rate_limited, n}}` surfacing) and reads
`scientificName` directly. **No ingestion code is modified.** Because we already hold
the authoritative `fdc_id`, this is the cheapest and highest-trust source — no name
search, no ambiguity — which is why USDA-derived names default to `0.9` confidence.

### 3.2 External identifier enrichment

The scientific name from USDA is the join key handed to the external id client
(behaviour `Mehungry.Food.IdentityResolution.ScientificIdClient`). The default live
implementation, `ExternalScientificIdClient`, uses public key-free APIs:

- **Wikidata** — `wbsearchentities` maps the name → Q-id (`wikidata_id`); the entity's
  claims yield the **NCBI Taxonomy ID** (property `P685`); English aliases become
  common-name synonyms.
- **EBI OLS4** — the Ontology Lookup Service search resolves the name → a **FoodOn**
  term (`foodon_id`).

Every sub-lookup is best-effort and defensive: network/parse failures are swallowed
and a partial result is returned, so external-API flakiness never fails a resolution.
HTTP goes through the `:identity_http_adapter` seam so tests run fully offline.

### 3.3 Orchestration (`IdentityResolution.resolve_ingredient/1`)

```
fetch USDA scientificName (by fdc_id)
 ├─ nil name            → record attempt "no_scientific_name";      {:ok, :no_scientific_name}
 ├─ name found          → resolve external ids (Wikidata + OLS)
 │                        → add_identity_candidate (find-or-create)
 │                        → add synonyms (idempotent)
 │                        → record attempt "matched";               {:ok, :matched}
 ├─ rate-limited / net  → (transient)                               {:error, reason}   # Oban retries
 └─ other USDA error    → record attempt "error";                   {:ok, :error}      # advance
```

`add_identity_candidate/1` is find-or-create on `(ingredient_id, scientific_name,
source)`; it returns `{:ok, identity, :created | :exists}` and **never mutates an
existing row**.

---

## 4. The pipeline (Oban run with retries + progress)

`Mehungry.ObanWorkers.IngredientIdentityResolutionWorker` mirrors
`TaxonomyClassificationWorker`:

- `use Oban.Worker, queue: :imports, max_attempts: 3` (concurrency 2 — gentle on external APIs).
- A single job threads a `run_id` through a **self-re-enqueueing chain**.
- Each tick: `mark_processing` → fetch a batch of up to **25** fdc-backed ingredients
  with no attempt yet → resolve each → `update_progress` on the run → enqueue the next
  batch. An empty batch marks the run `completed` and stops.
- **Termination** is guaranteed by the attempt ledger (every processed ingredient is
  excluded from the next batch).
- **Retries**: a transient failure (`{:error, {:rate_limited|network, _}}`) marks the
  run `failed` and returns `{:error, reason}` so Oban retries with backoff. The retry
  is idempotent because already-attempted ingredients are skipped.

### Starting a run

```elixir
{:ok, run} = Mehungry.Food.enqueue_resolution()
# opens an ingredient_identity_resolution_runs row and enqueues the first batch
```

Progress can be read at any time:

```elixir
Mehungry.Food.resolution_progress()          #=> %{resolved: 1234, total: 5000}
Mehungry.Food.latest_identity_resolution_run() #=> %IngredientIdentityResolutionRun{status: "processing", ...}
```

The run broadcasts `{:identity_resolution_run, run}` on `Mehungry.PubSub` topic
`"identity_resolution_runs"`. The admin **Science Pipeline** LiveView subscribes and
renders a live progress bar for this run as its stage 0 — `/professional/science` →
**Run resolution** (see `docs/scientific_pipeline.md` and §5.1 below).

---

## 5. Manual verification workflow

Candidates start as `status: "candidate"`. A reviewer promotes one:

```elixir
Mehungry.Food.list_pending_verification(limit: 50)      # candidates, lowest-confidence first
Mehungry.Food.verify_identity(identity_id, user_id)     # → verified
Mehungry.Food.reject_identity(identity_id, user_id)     # → rejected (kept)
Mehungry.Food.verified_identity(ingredient_id)          # the current verified one, or nil
Mehungry.Food.list_skipped_resolutions(limit: 25)       # attempts that yielded no identity
```

`verify_identity/2` runs in a transaction: any currently-`verified` identity for the
same ingredient is first marked **`superseded`** and chained via `superseded_by_id`
to the new one (never deleted), then the chosen identity becomes `verified`. This
preserves the full history of what was verified and when, and satisfies the
one-verified-per-ingredient partial unique index.

### 5.1 Reviewing outcomes in the admin UI

`/professional/science/identity-review` (the **Identity review** tab of the Science
Pipeline page — `MehungryWeb.ProfessionalLive.IdentityReviewComponent`) renders two
lists:

- **Identity verification** — the `list_pending_verification/1` queue with
  **Verify** / **Reject** buttons wired to `verify_identity/2` / `reject_identity/1`.
  Verifying is what promotes a candidate to `verified` — the status the literature
  crawler reads — so this queue gates the rest of the pipeline.
- **Skipped (no identity)** — a **read-only** list of fdc-backed ingredients that
  were processed but produced no identity, and *why*. It is backed by
  `list_skipped_resolutions/1`, which reads the attempt ledger for the non-match
  outcomes: `no_scientific_name` (shown as "No scientific name in USDA data") and
  `error` (shown with the reason from the attempt's `detail`). Nothing to action —
  it exists so an operator can see what fell out and why.

---

## 6. Configuration seams

All swappable via app config (defaults in parentheses):

| Key | Default | Purpose |
|---|---|---|
| `:usda_scientific_source` | `IdentityResolution.UsdaScientificSource` | Source of the USDA scientific name. |
| `:scientific_id_client` | `IdentityResolution.ExternalScientificIdClient` | External id resolver (Wikidata + OLS). Set to `NullScientificIdClient` to run USDA-name-only with no external calls. |
| `:identity_http_adapter` | `&HTTPoison.get/3` | HTTP for the external client; stubbed in tests. |
| `:fdc_api_key` (`FDC_API_KEY`) | — | Required for the USDA source (as for the rest of the FDC integration). |

Example — disable external calls in an environment:

```elixir
config :mehungry, :scientific_id_client, Mehungry.Food.IdentityResolution.NullScientificIdClient
```

---

## 7. Module map

| Module | File | Role |
|---|---|---|
| `Food.IdentityResolution` | `food/identity_resolution.ex` | Context: writes, queries, verification (incl. `list_skipped_resolutions/1`), orchestration, progress. |
| `Food.IdentityResolutionRuns` | `food/identity_resolution_runs.ex` | Run lifecycle + PubSub progress. |
| `Food.IngredientScientificIdentity` | `food/schemas/ingredient_scientific_identity.ex` | Candidate identity schema. |
| `Food.IngredientIdentitySynonym` | `food/schemas/ingredient_identity_synonym.ex` | Synonym schema. |
| `Food.IngredientIdentityResolutionAttempt` | `food/schemas/ingredient_identity_resolution_attempt.ex` | Ledger schema. |
| `Food.IngredientIdentityResolutionRun` | `food/schemas/ingredient_identity_resolution_run.ex` | Run schema. |
| `Food.IdentityResolution.UsdaScientificSource` | `food/identity_resolution/usda_scientific_source.ex` | USDA `scientificName` fetch. |
| `Food.IdentityResolution.ScientificIdClient` | `food/identity_resolution/scientific_id_client.ex` | External id behaviour. |
| `Food.IdentityResolution.ExternalScientificIdClient` | `.../external_scientific_id_client.ex` | Live Wikidata + OLS impl (default). |
| `Food.IdentityResolution.NullScientificIdClient` | `.../null_scientific_id_client.ex` | No-op impl / stub base. |
| `ObanWorkers.IngredientIdentityResolutionWorker` | `oban_workers/ingredient_identity_resolution_worker.ex` | Run chain worker. |
| `MehungryWeb.ProfessionalLive.SciencePipeline` | `mehungry_web/.../professional_live/science_pipeline.ex` | Admin panel; stage 0 = **Run resolution** + progress; hosts the review tab. |
| `MehungryWeb.ProfessionalLive.IdentityReviewComponent` | `mehungry_web/.../professional_live/identity_review_component.ex` | Verify/reject queue + read-only skipped list. |

All public context functions are also exposed via the `Mehungry.Food` facade (per the
facade convention in `CLAUDE.md`).

---

## 8. Guarantees recap

- **Never overwrites** — writes are find-or-create on natural keys.
- **Preserves history** — append-only; verification supersedes, never deletes.
- **Multiple candidates** — no unique constraint on `(ingredient, name)` alone; only on `(ingredient, name, source)`.
- **Confidence + provenance** — every row carries `confidence`, `source`, `id_source`, and an optional citation.
- **USDA-safe** — nothing in ingestion/reconciliation reads or writes these tables; ingredient rows are only referenced, never modified.

---

## 9. Testing & verification

- `apps/mehungry/test/mehungry/food/identity_resolution_test.exs` — context behavior:
  never-overwrite, multiple candidates, verification history (supersede chain +
  partial unique index), synonyms, and `resolve_ingredient/1` with stubbed USDA +
  id-client sources (the `"Spinach → Spinacia oleracea / NCBI 3562"` example).
- `apps/mehungry/test/mehungry/oban_workers/ingredient_identity_resolution_worker_test.exs`
  — the run pipeline: progress updates, termination, idempotent re-runs, and
  `{:error, _}` + retry on a transient source failure. Sources are stubbed via the
  app-env seams (offline).

Run:

```bash
mix test apps/mehungry/test/mehungry/food/identity_resolution_test.exs \
         apps/mehungry/test/mehungry/oban_workers/ingredient_identity_resolution_worker_test.exs
```

End-to-end (optional, needs `FDC_API_KEY` and network): seed a spinach ingredient with
its real `fdc_id`, run `Mehungry.Food.enqueue_resolution()`, and confirm a
`Spinacia oleracea` identity with NCBI/Wikidata ids appears and the run reaches
`completed`.

---

## 10. Known issues / caveats

Minor gaps between this document and the current implementation. None affects the
core guarantees in §8; they are tracked here so the doc and code stay honest.

- **`rank` is never populated.** `insert_resolution/3` writes `rank: ids[:rank]`,
  but neither `UsdaScientificSource` nor `ExternalScientificIdClient` ever returns a
  `:rank` key, so the column is always `nil` in practice. The `rank` field in §2 and
  the `optional(:rank)` in the `ScientificIdClient` behaviour describe a
  planned-but-unwired capability. Populating it (e.g. from the Wikidata "taxon rank"
  claim `P105`) is a follow-on.

- **The non-FDC guard clause skips the attempt ledger.** `resolve_ingredient/1`'s
  first clause returns `{:ok, :no_scientific_name}` for an ingredient with a
  `nil`/`≤0` `fdc_id` **without** recording an attempt. The §3.3 diagram's
  "nil name → record attempt" only actually fires on the *valid-fdc-but-blank-
  `scientificName`* path. This is harmless in the batch pipeline because
  `list_unresolved_ingredients/1` filters to `fdc_id > 0` (the guard clause is
  unreachable there), but a direct facade call on a non-FDC ingredient reports
  `:no_scientific_name` with no ledger row. A consequence: the **Skipped (no
  identity)** review (§5.1, `list_skipped_resolutions/1`) reads the attempt ledger,
  so it lists only *attempted* fdc-backed ingredients — non-FDC ingredients (never
  attempted) never appear there.

- **`notes` column is undocumented in §2.** The schema, migration, and
  `insert_resolution/3` (`notes: usda[:description]`) all carry a `notes` field; the
  §2 column table omits it.

- **`id_source` values `ncbi` / `foodon` / `manual` are allowed but never emitted**
  by the live client, which only sets `"wikidata"` or `"ols"` (via `put_id_source/1`).
  They remain valid for `manual`/`ai`-sourced rows added by other paths.
