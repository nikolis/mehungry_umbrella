# FAOSTAT production data — bundled subset

Source: **FAO FAOSTAT**, "Production: Crops and livestock products" (domain `QCL`),
element *Production* (tonnes). Licensed **CC BY 4.0** — attribution is required wherever
these values are surfaced (we render "Production data: FAO FAOSTAT (CC BY 4.0)" next to
the top-producers fact). See <https://www.fao.org/faostat/en/#data/QCL>.

## What's here

`production.csv` — a trimmed export keyed by FAOSTAT **item code**, one row per
`(item_code, country, year)` with the production tonnage. The species-enrichment pass
(`mix species.enrich --source faostat`) reads it via `FoodData.Faostat.Client`, and
`FoodData.Faostat.Parser.top_producers/3` picks the latest year's top-N producing
countries for a species' curated `faostat_item_code`.

Columns: `item_code,item,area,year,value_tonnes`.

## Refreshing / expanding

This bundled file is a **starter subset** covering common crops so the pipeline runs
offline and deterministically (mirrors `priv/unitools`, `priv/myplate`). To cover more
foods, download the full `Production_Crops_Livestock_E_All_Data` export from FAOSTAT,
filter to element *Production*, and append rows in the same shape. Only the **rank order**
of producing countries is surfaced to users (country names + source year, never raw
tonnage), so the display stays truthful even as exact tonnages are refreshed.

Map each species to its FAOSTAT item with `mix species.faostat_crosswalk` (fuzzy-matches
species names to the FAOSTAT item list for an admin to confirm into
`foundemental_food_species.faostat_item_code`).
