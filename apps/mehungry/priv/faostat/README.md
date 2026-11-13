# FAOSTAT production data — bundled subset

Source: **FAO FAOSTAT**, "Production: Crops and livestock products" (domain `QCL`),
element *Production* (tonnes). Licensed **CC BY 4.0** — attribution is required wherever
these values are surfaced (we render "Production data: FAO FAOSTAT (CC BY 4.0)" next to
the top-producers fact). See <https://www.fao.org/faostat/en/#data/QCL>.

## What's here

`production.csv` — derived from the full FAOSTAT QCL export, keyed by FAOSTAT **item
code**, one row per `(item_code, country, year)` with the production tonnage. It carries
the **top-4 producing countries of the latest year present** for **~259 primary crop and
livestock items** (the entire QCL primary taxonomy — cereals, pulses, nuts, oilcrops,
vegetables, fruit, spices, fibres, meat/dairy/eggs/honey). The species-enrichment pass
(`mix species.enrich --source faostat`) reads it via `FoodData.Faostat.Client`, and
`FoodData.Faostat.Parser.top_producers/3` picks the latest year's top-N producing
countries for a species' curated `faostat_item_code`.

Columns: `item_code,item,area,year,value_tonnes` (RFC-4180 quoted — several item names
and country names contain commas, e.g. `"Coffee, green"`, `"Côte d'Ivoire"`).

Only the **rank order** of producing countries is surfaced to users (country names +
source year, never raw tonnage), so the display stays truthful even as exact tonnages are
refreshed; the tonnages are kept solely to recompute that ranking.

## Refreshing / expanding

The file is generated from FAOSTAT's public bulk export — **not hand-curated** — so a
refresh is a re-run, not an append:

1. Download `Production_Crops_Livestock_E_All_Data_(Normalized).zip` from
   <https://bulks-faostat.fao.org/production/> and unzip the `…(Normalized).csv`.
2. Keep rows where **Element Code = 5510** (Production) and **Unit = `t`** (tonnes).
3. Drop regional/aggregate areas (**Area Code ≥ 5000**) and the China sub-entities
   (Area Codes 41/96/128/214) so **China** is listed once via the `351` aggregate.
4. Drop FAOSTAT aggregate/composite **items** (**Item Code ≥ 1700**: "Cereals, Total",
   "Meat, Total", "Fruit Primary", …) — generic names that mis-match a single species.
5. Per item, take the **latest year** present and its **top-4 countries** by tonnage.

(The one-off script used for the current file lived in the session scratchpad; the five
rules above fully specify it.) Coverage is bounded by FAOSTAT's own taxonomy — foods it
doesn't track as a distinct production item (e.g. acerola, arrowhead, amaranth) will have
no strong crosswalk match no matter how the file is refreshed.

Map each species to its FAOSTAT item with `mix species.faostat_crosswalk` (fuzzy-matches
species names to the FAOSTAT item list for an admin to confirm into
`foundemental_food_species.faostat_item_code`).
