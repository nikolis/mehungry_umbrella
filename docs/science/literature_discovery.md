# Literature context

`Mehungry.Literature` is the scientific-literature **discovery layer** for the
food domain. It finds research papers connecting a **food species** (by its
curated scientific name) to bioactive compounds, and records each paper as a
first-class `ScientificStudy` linked back to every ingredient curated onto that
species and — when the search matches the compound registry — the compound.

NCBI Entrez (PubMed) is treated as an external authority in exactly the way USDA
is for ingredients and PubChem is for compounds: a crawler turns each
`FoundementalFoodSpecies`' `scientific_name` into a set of searches and **syncs the
results into `Mehungry.Literature`**. The rest of the application never talks to
Entrez — it only reads `Mehungry.Literature`.

```
        USDA    ──▶ canonical ingredient registry   (Food.Ingredients)
        PubChem ──▶ canonical compound registry     (Food.Compounds)
        PubMed  ──▶ scientific-study registry        (Literature)          ← this doc
```

Once a study is discovered, **NCBI PubTator3** annotates it into `StudyEntityMention`
facts (Chemicals, Species, Diseases) — a sibling adapter in this same context. See
**`docs/science/pubtator.md`**.

---

## 1. Why this exists

Food species carry a curated `scientific_name` (`Spinacia oleracea` — set in the
USDA Schema view) and compounds carry chemical identities (`docs/science/chemistry.md`),
but there was no **evidence layer**: the published research that links the two. This layer adds it as an importer/adapter, not a data store —
it discovers and catalogues papers, it does not assert dietary facts.

**Boundaries honored:**

- No existing table is altered; USDA ingestion / reconciliation is untouched.
- Studies are **facts about the literature**, never dietary advice. Co-occurrence
  of an ingredient and a compound in a paper never writes an
  `IngredientCompoundRelationship` — that stays a separate, human-curated step.
- The full raw E-utilities payload is never lost — every response is stored
  append-only.
- PubMed is not hard-coded as the only source: `StudyIngredient.source` and the
  raw-cache endpoint enum leave room for other literature sources later.

---

## 2. Architecture

```
        NCBI Entrez E-utilities  (external authority)
                 │  esearch → PMIDs ;  efetch (XML) → title/abstract/authors/journal/date/DOI
                 ▼
  Literature.Entrez  (crawler / discovery adapter — never queried by the app)
        ├── search terms ───────▶ scientific_studies         (PMID-keyed registry)
        │                          ├─ study_ingredients        (study↔ingredient, fanned out to the species' ingredients + search-term provenance)
        │                          └─ study_compounds          (study↔compound)
        ├── raw payload ────────▶ entrez_responses            (append-only cache)
        └── ledger ─────────────▶ literature_crawl_attempts   (per (species, term) dedup + watermark)

  LiteratureCrawlWorker  (Oban :imports queue, self-re-enqueuing run chain)
        └── literature_crawl_runs   (aggregate progress + PubSub)
```

### `scientific_studies` — paper registry (deduped by PMID)
One row per paper, keyed by PubMed `pmid` (unique). Columns: `doi`, `title`,
`abstract`, `journal`, `publication_date` (kept as the raw irregular PubMed
string, like `ingredients.publication_date`), `authors` (`text[]`),
`raw_metadata` (jsonb, for extra efetch fields), `retrieved_at`.

### `study_ingredients` / `study_compounds` — the join facts
`study_ingredients` carries the exact `search_term` that surfaced the paper
(e.g. `"Spinacia oleracea oxalate"`) and a `scientific_name` snapshot; unique on
`(study_id, ingredient_id, search_term)`. `study_compounds` links to a registry
`Compound` only when the term matched one; unique on `(study_id, compound_id)`.

### `entrez_responses` — raw API cache (append-only)
One row per successful `esearch`/`efetch` fetch; never overwritten. efetch XML is
decoded to a map before storage so the cache stays queryable. Also the durable
search→PMID cache: `latest_search_pmids/1` reads the newest `esearch` row.

### `literature_crawl_attempts` — per-`(species, term)` ledger
`outcome` (`matched | no_results | error`), `studies_found`, `last_crawled_at`.
Unique on `(foundemental_species_id, search_term)` (upsertable). This is what makes
the batch crawl terminate — already-attempted pairs are excluded from the next batch —
and `last_crawled_at` is the incremental-crawl watermark.

---

## 3. The crawler (`Mehungry.Literature.Entrez`)

```elixir
Mehungry.Literature.import_species(spinach_species.id)
#=> {:ok, 3}   # three studies discovered/synced across this species' terms
```

**Search-term builder** — `search_terms_for_species/1` builds
`scientific_name × (compounds already linked to the species' ingredients ∪ a fixed
phytochemistry keyword set)`:

```
Spinacia oleracea Oxalate       -> StudyCompound(Oxalate)   (compound registry match)
Spinacia oleracea polyphenol    -> ingredient link only     (class term)
Spinacia oleracea phytochemical -> ingredient link only     (generic)
```

The scientific name is read from the species' curated `scientific_name`; a species
with no name yields no terms (defensively ledgered so the batch still terminates).
Each matched study is fanned out to **every ingredient curated onto the species**
(one `study_ingredients` row per ingredient per distinct term).

Flow (idempotent, cached, history-preserving) per term:

```
esearch(term)  → PMIDs   (hot :entrez_cache → durable entrez_responses → Client)
 ├─ []          → ledger "no_results"
 └─ PMIDs       → efetch(PMIDs) (store raw)
                  → upsert_study/1 per paper (dedup on pmid)
                  → link_study_ingredient/1  (+ link_study_compound/1 if the term carried a compound)
                  → ledger "matched", studies_found: n
 transient {:error, {:rate_limited|network, _}} → bubble up (worker snoozes/retries; NOT ledgered)
```

- **Dedup by PMID.** A paper found under several terms converges on one
  `scientific_studies` row; one `study_ingredients` row per distinct term.
- **Incremental.** A `:refresh` crawl restricts `esearch` to papers newer than the
  term's `last_crawled_at` (`mindate`), so re-crawls fetch only new evidence.

`upsert_study/1` (`on_conflict` on `pmid`), `link_study_ingredient/1` /
`link_study_compound/1` (`on_conflict: :nothing`), and `record_crawl_attempt/1`
are the deduping write seams in `Mehungry.Literature`.

---

## 4. HTTP client (`Mehungry.Literature.Entrez.Client`)

An E-utilities client modeled on `Mehungry.Chemistry.PubChem.Client`:

- `esearch/2` (JSON) → `{:ok, pmids, count, raw}`; `efetch/2` (XML, parsed with
  `SweetXml`) → `{:ok, [study_attrs], raw}`;
- bounded exponential-backoff retry on network errors and 5xx;
- `429`/`503` throttles with a short `Retry-After` are absorbed in-process; a hard
  throttle surfaces as `{:error, {:rate_limited, seconds}}`;
- `404`/empty maps to `{:error, :not_found}`;
- enforces NCBI's ceiling via `Mehungry.RateLimit` — **3 req/s** without an API
  key, **10 req/s** with one.

Config seams:

| Key | Default | Purpose |
|---|---|---|
| `:entrez_http_adapter` | `&HTTPoison.get/3` | HTTP call; stubbed in tests. |
| `:entrez_base_url` | `https://eutils.ncbi.nlm.nih.gov/entrez/eutils` | API root. |
| `:entrez_rate_limit` | `3` (`10` w/ key) | Local req/s ceiling (lifted in tests). |
| `:entrez_api_key` (`NCBI_API_KEY`) | `nil` | Optional; lifts the ceiling to 10. |

The hot search→PMID cache is the `:entrez_cache` Cachex instance started in
`Mehungry.Application`.

---

## 5. The pipeline (Oban run with retries + progress)

`Mehungry.ObanWorkers.LiteratureCrawlWorker`:

- `use Oban.Worker, queue: :imports, max_attempts: 3` (concurrency 2 — gentle on
  the API).
- A single job threads a `run_id` through a self-re-enqueueing chain. Each tick:
  `mark_processing` → a batch of up to **10** named species (with a `scientific_name`)
  with no crawl attempt yet → `import_species/1` each (paced by `:entrez_pace_ms`) →
  `update_progress` → enqueue the next batch. An empty batch marks the run
  `completed` and stops.
- **Termination** is guaranteed by the ledger.
- **Rate limits / retries**: a `{:error, {:rate_limited, n}}` short-circuits into
  an Oban `{:snooze, clamp(n)}` (bounded by `:entrez_max_snooze_seconds`); other
  transient errors mark the run `failed` and return `{:error, _}` for backoff.
  Both are idempotent because ledgered pairs are skipped on the retry.

### Starting a run

```elixir
{:ok, run} = Mehungry.Literature.enqueue_crawl()
```

Progress: `Mehungry.Literature.crawl_progress()` → `%{processed: _, total: _}`;
`Mehungry.Literature.CrawlRuns.latest_run()`. Every transition broadcasts
`{:literature_crawl_run, run}` on `Mehungry.PubSub` topic `"literature_crawl_runs"`
for a live progress bar (the LiveView is a follow-on).

---

## 6. Read API (for later UIs)

```elixir
Mehungry.Literature.list_studies_for_ingredient(ingredient_id)  # [%ScientificStudy{}]
Mehungry.Literature.list_studies_for_compound(compound_id)      # [%ScientificStudy{}]
Mehungry.Literature.list_ingredients_for_study(study_id)        # [%Ingredient{}]
Mehungry.Literature.get_study_by_pmid(pmid)
```

---

## 7. Module map

| Module | File | Role |
|---|---|---|
| `Literature` | `literature.ex` | Context: registry/link CRUD, raw cache, ledger, queries, `enqueue_crawl`. |
| `Literature.Entrez` | `literature/entrez.ex` | Crawler / discovery adapter. |
| `Literature.Entrez.Client` | `literature/entrez/client.ex` | E-utilities HTTP client (retry + rate limit). |
| `Literature.Entrez.RawResponse` | `literature/entrez/raw_response.ex` | Append-only raw-payload schema. |
| `Literature.ScientificStudy` | `literature/scientific_study.ex` | PMID-keyed paper registry schema. |
| `Literature.StudyIngredient` | `literature/study_ingredient.ex` | Study↔ingredient fact schema. |
| `Literature.StudyCompound` | `literature/study_compound.ex` | Study↔compound fact schema. |
| `Literature.CrawlAttempt` | `literature/crawl_attempt.ex` | Per-`(ingredient, term)` ledger schema. |
| `Literature.CrawlRun` | `literature/crawl_run.ex` | Aggregate run schema. |
| `Literature.CrawlRuns` | `literature/crawl_runs.ex` | Run lifecycle + PubSub progress. |
| `ObanWorkers.LiteratureCrawlWorker` | `oban_workers/literature_crawl_worker.ex` | Run-chain crawl worker. |

---

## 8. Testing

```bash
mix test test/mehungry/literature/ \
         test/mehungry/oban_workers/literature_crawl_worker_test.exs
```

- `entrez/client_test.exs` — esearch JSON parse, efetch XML parse, empty/`404` →
  `:not_found`, `503` retry-then-succeed, long `Retry-After` → `{:rate_limited, _}`,
  network-error retry. Fully offline via the `:entrez_http_adapter` stub.
- `entrez_test.exs` — the spinach/oxalate worked example (study fields + ingredient
  and compound links), PMID dedup across terms, generic-keyword path (ingredient
  link, no compound link), idempotent re-crawl (zero HTTP via the ledger),
  append-only raw storage, and the no-scientific-name ledger case.
- `literature_crawl_worker_test.exs` — batch crawl + progress + chaining, run
  completion/stop, and `{:snooze, _}` on a rate limit.

End-to-end (optional; needs network, `NCBI_API_KEY` optional): curate a spinach
ingredient onto a `FoundementalFoodSpecies` with `scientific_name: "Spinacia
oleracea"`, run `Mehungry.Literature.enqueue_crawl()`, and confirm real PubMed
studies appear linked to the ingredient and the run reaches `completed`.

---

## 9. Out of scope / follow-ons

- No LiveView progress bar yet — the data + PubSub broadcasts are in place.
- No promotion of studies into `IngredientCompoundRelationship` facts — the crawler never
  asserts a dietary fact. That curation step now exists as `Food.CompoundCandidates`
  (**`docs/science/compound_candidates.md`**); promoted relationships feed back into
  `search_terms_for_species/1` as targeted crawl terms.
- Additional literature sources (Europe PMC, Semantic Scholar, CrossRef) reuse the
  `study_ingredients.source` field and the raw-cache layer.
