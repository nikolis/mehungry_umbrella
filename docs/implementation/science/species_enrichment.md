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
mix species.enrich  ──▶  Wikidata.Client.fetch/2 ─┐
   (per species)         Faostat.Parser.top_producers/3 ─┤
                                                        ▼
                     Food.SpeciesEnrichment.record_{wikidata,faostat}_facts
                                                        ▼
                     pending SpeciesFact rows  ──▶  /professional/species-enrichment
                                                        │ (admin promote / reject)
                                                        ▼
                     promoted facts  ──▶  species detail page + /api/v1/species/:slug
```

Nothing surfaces until an admin **promotes** it — external identity-matching (a Wikidata
top-hit for an ambiguous name) can be wrong. `rejected` is sticky: a re-fetch upserts only
extraction fields (`value_*`, `confidence`, source, `retrieved_at`), never `status`.

### Context — `Mehungry.Food.SpeciesEnrichment`
`record_wikidata_facts/2` · `record_faostat_facts/2` · `upsert_fact/1` ·
`promote_fact/1` · `reject_fact/1` · `list_pending_facts/1` · `list_promoted_facts/1` ·
`promoted_facts_for_species/2` (promoted + locale-resolved: requested locale → `en` →
locale-independent). All exposed on the `Mehungry.Food` facade as `*_species_fact(s)`.

### Clients (offline-testable seams)
- `FoodData.Wikidata.Client` behind `ClientBehaviour` (`:wikidata_client`); HTTP behind
  `:wikidata_http_adapter` so parsing is unit-tested offline. Mirrors
  `Food.IdentityResolution.ExternalScientificIdClient`.
- `FoodData.Faostat.{Client, Parser}` behind `ClientBehaviour` (`:faostat_client`);
  data is a **bundled** trimmed CSV in `priv/faostat/production.csv` (offline,
  deterministic — like `priv/unitools`/`priv/myplate`), cached a day. `README` there
  explains refreshing from the full FAOSTAT export.

### Mix tasks
- `mix species.faostat_crosswalk [--all] [--threshold F]` — fuzzy-matches species names to
  the FAOSTAT item list and prints suggested `faostat_item_code`s for an admin to confirm.
- `mix species.enrich [--source wikidata|faostat|all] [--only SLUG]` — fetches facts into
  the review queue.

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
- `apps/mehungry/test/mehungry/food_data/faostat/parser_test.exs` — latest-year top-N.
- `apps/mehungry/test/mehungry/food_data/wikidata/client_test.exs` — parse via the HTTP seam.
- `apps/mehungry_web/.../food_health_test.exs` — the API `facts` block (only promoted).
- `apps/mehungry_web/.../live/species_detail_enrichment_test.exs` — the dead-render section.
