# PubTator3 context

The PubTator3 integration is the scientific-literature **entity-extraction layer**
for the food domain. Given a discovered `ScientificStudy`, it identifies the
**Chemicals, Species, and Diseases** mentioned in the paper and records each as a
first-class `StudyEntityMention` — an extracted fact, never an inference.

NCBI PubTator3 is treated as an external authority in exactly the way USDA is for
ingredients, PubChem for compounds, and Entrez for papers: an annotator normalizes
a study's PMID into a set of entity mentions and **syncs them into
`Mehungry.Literature`**. The rest of the application never talks to PubTator — it
only reads `Mehungry.Literature`.

The same BioC-JSON payload also carries a document-level **`relations`** array —
directional co-mentions (`Negative_Correlation` / `Positive_Correlation` /
`Association` / `Cotreatment`) between two entities. These are parsed by
`PubTator.Client.parse_relations/1` and stored as `StudyEntityRelation` rows with
**both endpoints resolved** (chemical → `Food.Compound`, disease → `Health.Condition`);
`Literature.remine_relations/0` back-fills them from payloads already on disk. Unlike
mentions, a chemical↔disease relation carries *direction*, which is what feeds the
review-gated `Health.RecommendationCandidates` — see
`docs/science/pubtator_relations_recommendations.md`.

```
        USDA     ──▶ canonical ingredient registry   (Food.Ingredients)
        PubChem  ──▶ canonical compound registry     (Food.Compounds)
        PubMed   ──▶ scientific-study registry        (Literature)
        PubTator3 ─▶ study entity mentions            (Literature)          ← this doc
```

---

## 1. Why this exists

Papers are discovered (`docs/science/literature_discovery.md`) and compounds carry chemical
identity (`docs/science/chemistry.md`), but there was no **entity layer**: the specific
chemicals, organisms, and diseases a paper actually mentions. This layer adds it as
an importer/adapter — it extracts and catalogues mentions, it does not assert
dietary facts.

**The hard requirements (and how they are honored):**

- **Do not infer relationships.** A mention's co-occurrence with an ingredient or
  compound never writes an `IngredientCompoundRelationship`. A chemical mention's
  `compound_id` is an *identity* link (normalization), not a dietary assertion.
- **Only capture extracted facts.** A row records the entity type, the identifier
  PubTator assigned, the preserved surface text, its offset, and any confidence —
  nothing derived.
- **Preserve the original text.** `text_span` stores the exact mention as written.
- **Preserve the source.** Every raw BioC JSON payload is retained append-only in
  `pubtator_responses`; `source` on the mention records the extractor.

---

## 2. Architecture

```
        NCBI PubTator3  (external authority)
                 │  export/biocjson?pmids=…  → BioC JSON annotations
                 ▼
  Literature.PubTator  (annotator / extraction adapter — never queried by the app)
        ├── mentions ───────────▶ study_entity_mentions        (extracted facts)
        │      └─ chemical → Chemistry.Resolver → compounds     (identity link only)
        ├── raw payload ────────▶ pubtator_responses           (append-only cache)
        └── ledger ─────────────▶ pubtator_annotation_attempts (per-study dedup)

  PubTatorAnnotationWorker  (Oban :imports queue, self-re-enqueuing run chain)
        └── pubtator_annotation_runs   (aggregate progress + PubSub)
```

### `study_entity_mentions` — the extracted facts

| Column | Meaning |
|---|---|
| `study_id` | FK → `scientific_studies` (`on_delete: delete_all`). |
| `entity_type` | `chemical \| species \| disease`. |
| `normalized_identifier` | Namespaced id **exactly as PubTator emitted it** — `mesh:D010070` (chemical/disease), `ncbitaxon:3562` (species). Nil when PubTator left the mention unnormalized (`"-"`). |
| `text_span` | The preserved original surface text of the mention. |
| `offset` | Character offset — distinguishes repeated mentions of the same entity. |
| `confidence` | Annotator score when present, else nil. |
| `source` | `"pubtator3"`. |
| `compound_id` | FK → `compounds` (`on_delete: nilify_all`) — set only for a chemical whose identity resolved. An identity link, never a dietary fact. |

**Natural key** (unique): `(study_id, entity_type, normalized_identifier, offset)`
— re-annotating a study upserts. Each distinct mention location is one row.

**MeSH stays primary.** The mention carries the MeSH id PubTator assigns; the
PubChem CID (and ChEBI/CAS/InChIKey) live on the resolved `compounds` row via
`compound_identifiers`, reachable through the resolver — not copied onto the mention.

### `pubtator_responses` — raw API cache (append-only)
One row per successful `export/biocjson` fetch; never overwritten. Reproducibility,
debugging, re-annotation, resilience against PubTator schema changes.

### `pubtator_annotation_attempts` — per-study ledger
`outcome` (`annotated | no_results | error`), `mentions_found`,
`last_annotated_at`. Unique on `study_id`. This is what makes the batch annotation
terminate — already-attempted studies are excluded from the next batch.

---

## 3. The annotator (`Mehungry.Literature.PubTator`)

```elixir
Mehungry.Literature.annotate_study(study.id)
#=> {:ok, 4}   # four entity mentions extracted/synced
```

Flow (idempotent, cached, history-preserving) per study:

```
export/biocjson([pmid])  → mentions   (hot :pubtator_cache → Client)
 ├─ []          → ledger "no_results"
 └─ mentions    → per mention:
        chemical → Chemistry.Resolver.resolve(mesh id ∪ name) → compound_id (or nil)
        species/disease → stored with namespaced id, no compound link
        → upsert_entity_mention/1 (dedup on the natural key)
      ledger "annotated", mentions_found: n
 transient {:error, {:rate_limited|network, _}} → bubble up (worker snoozes/retries)
```

- **Chemicals** route through `Mehungry.Chemistry.Resolver` (see `docs/science/chemistry.md`):
  identifier-first with the MeSH id (`{namespace: "mesh", identifier: …, name:
  text_span}`), falling back to the surface text as a name-only anchor. A resolved
  compound sets `compound_id`; an unresolvable one still stores the mention
  (unlinked). A transient resolver failure bubbles up for the worker to retry.
- **Species / Diseases** are stored with their namespaced identifier and no
  resolution.
- **Dedup by offset.** The same entity mentioned twice yields two rows (distinct
  offsets); re-annotating the study upserts rather than duplicates.

---

## 4. HTTP client (`Mehungry.Literature.PubTator.Client`)

A BioC JSON client modeled on `Mehungry.Literature.Entrez.Client`:

- `annotate/2` → `GET publications/export/biocjson?pmids=<csv>` →
  `{:ok, [mention_attrs], raw}`; walks `documents → passages → annotations`, keeps
  only `Chemical`/`Species`/`Disease`, and normalizes each identifier to its
  namespace (`mesh:…` / `ncbitaxon:…`);
- bounded exponential-backoff retry on network errors and 5xx;
- `429`/`503` throttles with a short `Retry-After` are absorbed in-process; a hard
  throttle surfaces as `{:error, {:rate_limited, seconds}}`;
- `404`/empty maps to `{:error, :not_found}`;
- enforces NCBI's ceiling via `Mehungry.RateLimit` (**3 req/s**, **10** with a key).

Config seams:

| Key | Default | Purpose |
|---|---|---|
| `:pubtator_http_adapter` | `&HTTPoison.get/3` | HTTP call; stubbed in tests. |
| `:pubtator_base_url` | `https://www.ncbi.nlm.nih.gov/research/pubtator3-api` | API root. |
| `:pubtator_rate_limit` | `3` (`10` w/ key) | Local req/s ceiling (lifted in tests). |
| `:entrez_api_key` (`NCBI_API_KEY`) | `nil` | Shared NCBI key; lifts the ceiling to 10. |

The hot pmid→mentions cache is the `:pubtator_cache` Cachex instance started in
`Mehungry.Application`.

---

## 5. The pipeline (Oban run with retries + progress)

`Mehungry.ObanWorkers.PubTatorAnnotationWorker` mirrors `LiteratureCrawlWorker`:

- `use Oban.Worker, queue: :imports, max_attempts: 3` (batch of up to **10**
  studies).
- A single job threads a `run_id` through a self-re-enqueueing chain: a batch of
  studies with no annotation attempt → `annotate_study/1` each (paced by
  `:pubtator_pace_ms`) → `update_progress` → enqueue the next batch. An empty batch
  marks the run `completed` and stops.
- **Termination** is guaranteed by the ledger.
- **Rate limits / retries**: `{:error, {:rate_limited, n}}` → Oban `{:snooze,
  clamp(n)}` (bounded by `:pubtator_max_snooze_seconds`); other transient errors
  mark the run `failed` and return `{:error, _}` for backoff. Both are idempotent
  because ledgered studies are skipped on the retry.

### Starting a run

```elixir
{:ok, run} = Mehungry.Literature.enqueue_annotation()
```

Progress: `Mehungry.Literature.annotation_progress()` → `%{processed: _, total: _}`;
`Mehungry.Literature.AnnotationRuns.latest_run()`. Every transition broadcasts
`{:pubtator_annotation_run, run}` on `Mehungry.PubSub` topic
`"pubtator_annotation_runs"` for a live progress bar (the LiveView is a follow-on).

---

## 6. Read API (for later UIs)

```elixir
Mehungry.Literature.list_entity_mentions_for_study(study_id)  # [%StudyEntityMention{}]
Mehungry.Literature.list_mentions_by_type(study_id, "chemical")
Mehungry.Literature.list_studies_for_compound_mention(compound_id)
```

---

## 7. Module map

| Module | File | Role |
|---|---|---|
| `Literature.PubTator` | `literature/pubtator.ex` | Annotator / extraction adapter. |
| `Literature.PubTator.Client` | `literature/pubtator/client.ex` | BioC JSON HTTP client (retry + rate limit). |
| `Literature.PubTator.RawResponse` | `literature/pubtator/raw_response.ex` | Append-only raw-payload schema. |
| `Literature.StudyEntityMention` | `literature/study_entity_mention.ex` | Extracted-mention fact schema. |
| `Literature.AnnotationAttempt` | `literature/annotation_attempt.ex` | Per-study ledger schema. |
| `Literature.AnnotationRun` | `literature/annotation_run.ex` | Aggregate run schema. |
| `Literature.AnnotationRuns` | `literature/annotation_runs.ex` | Run lifecycle + PubSub progress. |
| `ObanWorkers.PubTatorAnnotationWorker` | `oban_workers/pubtator_annotation_worker.ex` | Run-chain annotation worker. |

---

## 8. Testing

```bash
mix test apps/mehungry/test/mehungry/literature/pubtator/client_test.exs \
         apps/mehungry/test/mehungry/literature/pubtator_test.exs \
         apps/mehungry/test/mehungry/oban_workers/pubtator_annotation_worker_test.exs
```

- `pubtator/client_test.exs` — BioC JSON parse (Chemical/Species/Disease kept, Gene
  dropped), namespace normalization, `"-"` → nil, empty/`404` → `:not_found`, `503`
  retry-then-succeed, long `Retry-After` → `{:rate_limited, _}`. Offline via the
  `:pubtator_http_adapter` stub.
- `pubtator_test.exs` — the oxalate/spinach worked example (chemical resolves to a
  compound with MeSH kept as the identifier; species → `ncbitaxon:*` unlinked),
  offset-based dedup, idempotent re-annotate (zero HTTP via the ledger), append-only
  raw storage, and the no-`IngredientCompoundRelationship` guarantee.
- `pubtator_annotation_worker_test.exs` — batch + progress + chaining, run
  completion/stop, and `{:snooze, _}` on a rate limit.

---

## 9. Out of scope / follow-ons

- No LiveView progress bar yet — the data + PubSub broadcasts are in place.
- No promotion of mentions into `IngredientCompoundRelationship` facts — the annotator
  never asserts a dietary fact. That human-curation step now exists as
  `Food.CompoundCandidates` (**`docs/science/compound_candidates.md`**), which reads these mentions
  as co-occurrence evidence, scores candidate relationships, and promotes the strong ones.
- Genes, variants, and cell lines are annotated by PubTator3 but not captured — the
  integration is scoped to Chemicals, Species, and Diseases.
```
