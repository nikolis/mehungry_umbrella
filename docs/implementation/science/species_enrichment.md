# Species enrichment — origins & cultivation facts

Provenance-cited "interesting info" attached to each `FoundementalFoodSpecies` and
surfaced in the **/foods "Origins & cultivation"** section (species detail page +
mobile API): where a food comes from, where it's grown, a short description, a Wikipedia
link. It fills the gap between the species' taxonomy/nutrition/chemistry story and the
food as a *cultivated, geographic, real-world thing* — and is crawlable SEO content on
the deep `/foods/*` pages the A–Z directory funnels link equity into.

> **Glycemic index is deliberately NOT part of this.** GI has no licensable source and no
> data — see [`glycemic_index_licensing.md`](glycemic_index_licensing.md). Species
> enrichment is a separate, shipped pipeline.

## Sources & licensing

| Source | Facts | Licence | Obligation |
|---|---|---|---|
| **Wikidata** | `origin_region`, `description` (en/el), `wikipedia_url` (en/el) | **CC0** (public domain) | None (we link the entity courteously) |
| **FAOSTAT** — Production: Crops & livestock products (QCL) | `top_producers` | **CC BY 4.0** | **Attribution required** — rendered as "Production data: FAO FAOSTAT (CC BY 4.0)" next to the fact |

Only the **rank order** of producing countries is surfaced (country names + source year,
never raw tonnage), so the display stays truthful as FAOSTAT tonnages are refreshed.

**Promotion policy:** FAOSTAT `top_producers` facts **auto-promote** on fetch (keyed on a
curated item code → no identity-mismatch risk); Wikidata facts land **`pending`** and need
admin review before they surface (a top-hit for an ambiguous *taxon* name can be wrong).

**Coverage reality:** Wikidata reliably yields `description` + `wikipedia_url`;
`origin_region` is best-effort (the `P495`/`P2341`/`P183` origin properties are often
absent on *taxon* items). FAOSTAT covers only species an admin has crosswalked to a
FAOSTAT item code. The section renders whatever is promoted — partial is fine.

## Data model

- **`species_facts`** (`Mehungry.Food.SpeciesFact`) — one provenance-cited fact per row:
  `fact_key` (`origin_region|description|wikipedia_url|top_producers`), `value_text` /
  `value_json` (producers list), `locale` (`"en"`/`"el"`, or `""` for locale-independent
  facts — NOT NULL so the natural-key unique index dedups on re-fetch), `status`
  (`pending → promoted | rejected`), `enrichment_source_id`. Unique on
  `(foundemental_species_id, fact_key, locale, source)`.
- **`foundemental_food_species.faostat_item_code`** — curated crosswalk to a FAOSTAT
  item; nullable (many species have no FAOSTAT item).
- **Provenance reuses `ingredient_enrichment_sources`** (`Food.IngredientEnrichmentSource`
  — the shared citation registry): a Wikidata entity is a `url` source (identifier =
  Q-id), FAOSTAT is one `dataset` source (identifier = `faostat_qcl`).

## Pipeline

```
"Enrich all species" (/professional/species-enrichment)   ── admin trigger
   │  mix species.enrich (local equivalent)
   ▼
SpeciesEnrichmentRuns.enrich_all_species  ──▶  one SpeciesEnrichmentWorker job / species
   (one pending run row / species, grouped by batch_id, :species_enrichment queue)
                                                        ▼
                     Food.enrich_species/2 ──▶ Wikidata.Client.fetch/2 ─┐
                                               Faostat.Parser.top_producers/3 ─┤
                                                        ▼
                     Food.SpeciesEnrichment.record_{wikidata,faostat}_facts
                                                        ▼
       FAOSTAT facts  ── auto-promoted ───────────┐
       Wikidata facts ── pending ──▶ admin promote / reject (same page)
                                                        ▼
                     promoted facts  ──▶  species detail page + /api/v1/species/:slug
```

**Production trigger (the Oban-UI-connected pattern** — see
`docs/reference_architecture/oban_ui_connected_worker.md`**):** `mix species.enrich` only
runs locally, so the prod control is the **"Enrich all species"** card on
`/professional/species-enrichment`. It fans out one `SpeciesEnrichmentWorker` job per
species on the dedicated single-slot **`:species_enrichment`** queue (sequential, polite to
the Wikidata public API — *not* leader-gated/paused like `:fact_mining`, since Wikidata
needs no cluster-wide serialization), tracked by one `species_enrichment_runs` row per
species (`pending → processing → completed | failed`, `wikidata_count`/`faostat_count`),
broadcast over PubSub so the page streams each species finishing live (400 ms flush-timer
coalescing). **No reachability pre-flight:** a Wikidata/FAOSTAT failure degrades to 0 facts
and the job still completes. Both the worker and the mix task call the one shared
`Food.enrich_species/2`.

Wikidata facts don't surface until an admin **promotes** them (per-fact, or **"Promote all
pending"**) — external identity-matching (a top-hit for an ambiguous name) can be wrong.
`rejected` is sticky: a re-fetch upserts only extraction fields (`value_*`, `confidence`,
source, `retrieved_at`), never `status` (so auto-promoted FAOSTAT facts also keep their
status across re-fetches).

**FAOSTAT crosswalk (same page).** Because FAOSTAT only fetches for a species with a
`faostat_item_code`, the page carries a **"FAOSTAT crosswalk"** section to curate those
codes from the UI (replacing the console-only path). **"Run suggester"** calls
`Food.suggest_faostat_codes/1` (`SpeciesEnrichment.suggest_faostat_codes/1` →
`Faostat.Parser.suggest_item_code/2`, the same Jaro fuzzy-match `mix
species.faostat_crosswalk` uses — read-only), showing a `→ code item (score)` hint per
species; the admin **Apply**s a suggestion or types/edits the code and **Save**s (blank
clears it), persisted via `Food.update_foundemental_species/2`. Reachable from the admin
menu ("Species enrichment").

### Context — `Mehungry.Food.SpeciesEnrichment`
`enrich_species/2` (shared fetch+record for one species, returns `%{wikidata, faostat}` —
used by the worker **and** the mix task) · `record_wikidata_facts/2` ·
`record_faostat_facts/2` (sets `status: "promoted"`) · `upsert_fact/1` · `promote_fact/1` ·
`reject_fact/1` · `promote_all_pending_facts/0` · `list_pending_facts/1` ·
`list_promoted_facts/1` · `promoted_facts_for_species/2` (promoted + locale-resolved:
requested locale → `en` → locale-independent). All exposed on the `Mehungry.Food` facade
(the fetch/record ones as `*_species_fact(s)`; `enrich_species/2`, `load_faostat_rows/0`,
`promote_all_pending_species_facts/0` by name).

### Run tracking — `Mehungry.Food.SpeciesEnrichmentRuns` (+ `SpeciesEnrichmentRun`)
`enrich_all_species/0` (fan-out) · `mark_processing/1` · `mark_completed/2` ·
`mark_failed/2` · `latest_batch_id/0` · `list_batch_rows/1` · `counts_for_batch/1` ·
`batch_in_flight?/1` · `cancel_batch/1`. PubSub topic `"species_enrichment_runs"`. Mirrors
`Mehungry.FactMining.SpeciesFactMiningRuns` 1:1. Worker:
`Mehungry.ObanWorkers.SpeciesEnrichmentWorker` (`:species_enrichment` queue,
`max_attempts: 3`).

### Clients (offline-testable seams)
- `FoodData.Wikidata.Client` behind `ClientBehaviour` (`:wikidata_client`); HTTP behind
  `:wikidata_http_adapter` so parsing is unit-tested offline. Mirrors
  `Food.IdentityResolution.ExternalScientificIdClient`.
- `FoodData.Faostat.{Client, Parser}` behind `ClientBehaviour` (`:faostat_client`);
  data is a **bundled** CSV in `priv/faostat/production.csv` (offline, deterministic —
  like `priv/unitools`/`priv/myplate`), cached a day. It holds the latest-year **top-4
  producing countries for ~259 primary crop & livestock items** (the full QCL primary
  taxonomy), derived from FAOSTAT's bulk export; `README` there gives the exact
  regeneration recipe (element 5510 / unit `t`, drop aggregate areas + China sub-entities
  + aggregate items, latest-year top-4). `Parser.suggest_item_code/2` scores a species
  name against both the full item name and its pre-comma core, so verbose FAOSTAT names
  (`"Coffee, green"`) still match. Coverage is bounded by FAOSTAT's taxonomy — foods it
  doesn't track as a distinct item (acerola, arrowhead, amaranth…) have no strong match.

### Mix tasks
- `mix species.faostat_crosswalk [--all] [--threshold F]` — the CLI equivalent of the
  page's **"Run suggester"**: fuzzy-matches species names to the FAOSTAT item list (shared
  `Faostat.Parser.suggest_item_code/2`) and prints suggested `faostat_item_code`s for an
  admin to confirm. Read-only — curate the code from the UI (or a console update).
- `mix species.enrich [--source wikidata|faostat|all] [--only SLUG]` — the local equivalent
  of the "Enrich all species" prod trigger; calls the same `Food.enrich_species/2` (FAOSTAT
  auto-promoted, Wikidata into the review queue).

## Surfacing

- **Detail page** (`SpeciesDetailLive`) — "Origins & cultivation" `<section>`, fed by a
  `:facts` assign in `load_species_sidecars/2` loaded **synchronously on both renders**
  (so the facts are in the dead render crawlers index — unlike the heavier async
  compounds/recipes). Localized (gettext + Greek); producers carry the FAOSTAT credit.
- **Mobile API** — `GET /api/v1/species/:slug` → a `facts` block (`origin_region`,
  `description`, `wikipedia_url`, `top_producers: {countries, year, source}`). See
  `docs/implementation/new_dec_specs/mobile_api_spec.md` §8.
- Private species (`foundemental_food_species.private`) never surface — the detail page
  and API already resolve through the public scope.

## Tests
- `apps/mehungry/test/mehungry/food/species_enrichment_test.exs` — record/promote/reject,
  sticky-reject, locale resolution, idempotent upsert.
- `apps/mehungry/test/mehungry/food/species_enrichment_runs_test.exs` — fan-out opens one
  row + one job per species, lifecycle counts, cancel.
- `apps/mehungry/test/mehungry/oban_workers/species_enrichment_worker_test.exs` — the worker
  over stubbed clients: FAOSTAT auto-promoted, Wikidata pending, run completed with counts.
- `apps/mehungry_web/.../professional_live/species_enrichment_review_test.exs` — the admin
  page: "Enrich all species" fans out + streams a row to completed, "Promote all pending",
  admin gate.
- `apps/mehungry/test/mehungry/food_data/faostat/parser_test.exs` — latest-year top-N.
- `apps/mehungry/test/mehungry/food_data/wikidata/client_test.exs` — parse via the HTTP seam.
- `apps/mehungry_web/.../food_health_test.exs` — the API `facts` block (only promoted).
- `apps/mehungry_web/.../live/species_detail_enrichment_test.exs` — the dead-render section.
