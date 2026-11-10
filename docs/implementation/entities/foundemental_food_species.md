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
| `faostat_item_code` | string | optional **curated crosswalk** to a FAOSTAT crop/livestock item code — the key the top-producers enrichment (FAOSTAT, CC BY 4.0) joins on. Nullable: many species have no FAOSTAT item. Suggested by `mix species.faostat_crosswalk`. See [`../science/species_enrichment.md`](../science/species_enrichment.md). |
| `private` | boolean | default `false`. When `true` the species is **hidden from every public/consumer surface** — the `/foods` browse feed (EN/EL), name search, compound filter, A–Z directory, its `/foods/:slug` detail page (resolves to a 404), the sitemap, and the mobile API (`/api/v1/species` list + show) — while staying visible in the admin `/professional/usda-schema` "Foundemental Foods" view for curation. Enforced at the query layer: the `/foods`-only reads compose a `public_only` scope, the shared reads have explicit public variants (`Food.list_public_foundemental_species/0`, `Food.search_public_species/2`) the API uses, and `get_species_by_slug/1` filters private out so detail/API `show` 404. Toggled per species in the USDA-schema accordion ("Make private"/"Make public") or via the "Private" checkbox on the new-species modal. |

## Relationships

- `has_many :foundemental_foods` — the species ↔ ingredient curation (below)
- `has_many :translations` (FoundementalFoodSpeciesTranslation)
- Compound facts attach to species via `SpeciesCompoundRelationship` — see
  [`../science/food_compounds.md`](../science/food_compounds.md) and
  [`../science/compound_candidates.md`](../science/compound_candidates.md)
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

## Constraints

- Unique `[:name, :variety]`; required: `name`.

## Referenced by

[`../science/science.md`](../science/science.md) · [`../science/scientific_pipeline.md`](../science/scientific_pipeline.md) · [`../science/health_recommendations.md`](../science/health_recommendations.md) · [`ingredient.md`](ingredient.md)
