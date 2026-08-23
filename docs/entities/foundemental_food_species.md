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

## Relationships

- `has_many :foundemental_foods` — the species ↔ ingredient curation (below)
- `has_many :translations` (FoundementalFoodSpeciesTranslation)
- Compound facts attach to species via `SpeciesCompoundRelationship` — see
  [`../science/food_compounds.md`](../science/food_compounds.md) and
  [`../science/compound_candidates.md`](../science/compound_candidates.md)

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
