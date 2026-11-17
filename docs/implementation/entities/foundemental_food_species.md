# FoundementalFoodSpecies

Table `foundemental_food_species` · Schema `Mehungry.Food.FoundementalFoodSpecies`
(`food/schemas/foundemental_food_species.ex`). Index: [`entities.md`](entities.md).
*(Spelling "foundemental" kept throughout the codebase.)*

The botanical/zoological origin a USDA-backed [Ingredient](ingredient.md) ultimately maps
to (e.g. "Apple", "Cattle"). Its `scientific_name` is what **drives the literature
crawl** — see [`../science/science.md`](../science/science.md). Species (not ingredients)
are the key the compound facts and health advice hinge on.

## Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | required (e.g. "Apple") |
| `variety` | string | narrows it (e.g. "Gala") |
| `alternative_name` | string | |
| `scientific_name` | string | optional taxonomy — **drives the crawl** |
| `family` | string | optional taxonomy |
| `icon` | string | optional emoji **override**. When blank, `Mehungry.Food.species_icon/1` derives a default emoji from name/variety/family via `Mehungry.Food.SpeciesIcons` (name keyword → `family` → generic 🥗). Editable per species in the `/professional/usda-schema` tree; served on the `/api/v1/species` payloads. **Ingredient-level resolution:** `Mehungry.Food.ingredient_icons/1` maps logged/searched ingredients to an emoji through this species (override-aware), falling back to the ingredient's own English name when it isn't curated onto a species — drives the calendar meal cards and the ingredient search pickers. |
| `image_url` | string | optional **licence-gated Wikimedia Commons lead photo**, re-hosted on our storage, shown in place of the `icon` on `/foods` (detail hero + gallery cards) and exposed as the `image` object on `/api/v1/species`. Written by the species-enrichment sweep **only when the Commons licence is reusable** (CC0 / public domain / CC BY / CC BY-SA, via `Food.FoundementalFoods`'s `ImageLicense.reusable?/1`). Nil → emoji fallback. See [`../science/species_enrichment.md`](../science/species_enrichment.md). |
| `image_license` · `image_license_url` · `image_attribution` · `image_source_url` | string | the photo's attribution, always rendered next to it (even for CC0/PD): display licence name + its URL, the author, and the Commons file-page URL. Populated together with `image_url`. |
| `faostat_item_code` | string | optional **curated crosswalk** to a FAOSTAT crop/livestock item code — the key the top-producers enrichment (FAOSTAT, CC BY 4.0) joins on. Nullable: many species have no FAOSTAT item. Suggested by `mix species.faostat_crosswalk`. See [`../science/species_enrichment.md`](../science/species_enrichment.md). |
| `private` | boolean | default `false`. When `true` the species is **hidden from every public/consumer surface** — the `/foods` browse feed (EN/EL), name search, compound filter, A–Z directory, its `/foods/:slug` detail page (resolves to a 404), the sitemap, and the mobile API (`/api/v1/species` list + show) — while staying visible in the admin `/professional/usda-schema` "Foundemental Foods" view for curation. Enforced at the query layer: the `/foods`-only reads compose a `public_only` scope, the shared reads have explicit public variants (`Food.list_public_foundemental_species/0`, `Food.search_public_species/2`) the API uses, and `get_species_by_slug/1` filters private out so detail/API `show` 404. Toggled per species in the USDA-schema accordion ("Make private"/"Make public") or via the "Private" checkbox on the new-species modal. |

## Relationships

- `has_many :foundemental_foods` — the species ↔ ingredient curation (below)
- `has_many :translations` (FoundementalFoodSpeciesTranslation)
- Mined biomedical facts attach to species via `SpeciesMinedFact` (from the
  biomed-fact-miner) — see [`../fact_mining.md`](../fact_mining.md). *(The former
  `SpeciesCompoundRelationship` species↔compound graph was dropped 2026-11-12.)*
- Enrichment facts attach to species via `SpeciesFact` (below)

### SpeciesFact

Provenance-cited "Origins & cultivation" enrichment surfaced on `/foods/:slug`.
`Mehungry.Food.SpeciesFact` (`food/schemas/species_fact.ex`, table `species_facts`):

- `belongs_to :species` (FK `foundemental_species_id`, required), `belongs_to
  :enrichment_source` (shared `IngredientEnrichmentSource` citation registry).
- `fact_key` ∈ `origin_region | description | wikipedia_url | top_producers`;
  `value_text` / `value_json` (producers list); `locale` (`"en"`/`"el"`, or `""` for
  locale-independent facts — NOT NULL so the natural key dedups); `status`
  (`pending → promoted | rejected`); `confidence`; `retrieved_at`.
- Unique `(foundemental_species_id, fact_key, locale, source)`.
- Populated from **Wikidata (CC0)** + **FAOSTAT (CC BY 4.0)** by `mix species.enrich`,
  review-gated at `/professional/species-enrichment`. Only `promoted` facts surface. See
  [`../science/species_enrichment.md`](../science/species_enrichment.md).

### FoundementalFood

The `Species ↔ Ingredient` curation. `Mehungry.Food.FoundementalFood` (`food/schemas/foundemental_food.ex`, table
`foundemental_foods`) is the join that curates a concrete USDA
[Ingredient](ingredient.md) onto a species:

- `usda_name` (required) — snapshots the ingredient's USDA description at curation time.
- `belongs_to :species` (FK `foundemental_species_id`, required), `belongs_to :ingredient` (required).
- **Unique `ingredient_id`** — an ingredient belongs to **at most one** species.

**Curation UI (`/professional/usda-schema`, `MehungryWeb.ProfessionalLive.UsdaSchema`).** The page
leads with a **Find & assign console**: a name search (`phx-change "search"`, debounced) over the
whole *un-curated* universe — the union of every schema's matched rows and the unmatched pile, minus
the already-assigned ids — ranked by the shared `MehungryWeb.ProfessionalLive.ImportReviewSearch`
ranker. Matches stream into a checkbox list; selection (a `MapSet` persisted across queries, with
"Select all") collects in a sticky tray that assigns the **whole batch** to one species — existing or
a new one created inline — via `Food.assign_foundemental_ingredients/2`
(`FoundementalFoods.assign_ingredients/2`, which loops the single-row `assign_ingredient/3` so the
unique `ingredient_id` is honoured; an already-curated ingredient is counted **skipped**, never
fatal). The parser's schema-signature accordion (grouping by field pattern, with per-row single
assign) is retained but **demoted** to a collapsed "Structural view"; the "Foundemental Foods"
accordion below is the destination view (assigned leaves + per-species icon/visibility controls).
Each leaf there is **selectable** — ticking one or more surfaces a "Move to species" tray that
re-points the whole selection onto another species (existing or new) to fix a mis-assignment, via
`Food.move_foundemental_ingredients/2` (`FoundementalFoods.move_ingredients/2`, an `update_all` of
the join rows' `foundemental_species_id` — the `usda_name` snapshot and one-species-per-ingredient
invariant are preserved). Each expanded species node also carries an **"Edit details"** form
(`update_species_details` → `Food.update_foundemental_species/2`) to correct a mis-entered `name`,
`variety`, `scientific_name`, or `family` in place — blank `variety`/`scientific_name`/`family`
clear the column; `name` is required.

## Constraints

- Unique `[:name, :variety]`; required: `name`.

## Referenced by

[`../science/science.md`](../science/science.md) · [`../science/scientific_pipeline.md`](../science/scientific_pipeline.md) · [`../science/health_recommendations.md`](../science/health_recommendations.md) · [`ingredient.md`](ingredient.md)
