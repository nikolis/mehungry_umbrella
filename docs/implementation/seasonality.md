# Seasonality

Per food species × country × calendar month, two **independent** facts:

- **Local** — is the product locally on the market that month?
- **Imported** — is it imported that month, how much, and from where?

They are independent on purpose: imports often peak in the *same* months as the local
season (Greek tomatoes: imports from Turkey peak July–October), so "imported" is not
the complement of "local".

**Status (2026-11-24): admin-only v1.** Built on branch `seasonality-app`. There is no
public or `/api/v1` surface yet; `MehungrySeasonality.for_species/2` is the read seam a
future one would use. The core app reads it through one config seam
(`Mehungry.Food.SeasonalAvailability`, see [Core seam](#core-seam)) to pick seasonal
fruit for AI meal plans.

Contents: [Why](#why-it-exists) · [What a food needs to appear](#what-a-food-needs-to-appear) ·
[The separate app and its limits](#a-separate-umbrella-app--and-its-limits) ·
[Sources](#sources) · [Source research record](#source-research-record) ·
[Module map](#module-map) · [Data model](#data-model-seasonality_-tables) ·
[Fetch → derive](#fetch--derive) · [Admin page](#admin-page) ·
[Configuration](#configuration) · [Wiring outside the app](#wiring-outside-the-app) ·
[Runbook](#runbook) · [Tests](#tests) · [Known limits](#known-limits) ·
[Not built yet](#not-built-yet)

## Why it exists

The goal is a per-species, per-country, per-month availability picture ("this is
available now in Greece through local production / through import") to enrich the food
content diet-watchers learn from and nutritionists advise with. No single open source
publishes that, so it is **derived** from two official EU data feeds and then curated
by an admin.

## What a food needs to appear

1. It exists as a **`FoundementalFoodSpecies`** (the species, e.g. "Tomato" — not the
   individual `FoundementalFood` rows under it). Seasonality never creates species.
2. It has at least one **seasonality mapping** (below). Either side alone is enough;
   the unmapped side reads "No source".
3. A **fetch** has been run for the country.

The species' **`faostat_item_code` is not used** — that column belongs to the separate
species-enrichment feature ("top producing countries"). Seasonality has its own
crosswalk in its own table:

| Mapping (`source`) | What is entered | Gives |
|---|---|---|
| `agridata` (local) | the EU price portal's product name, e.g. `Tomatoes` | months it is locally on the market |
| `comext` (imports) | a 2–8 digit HS/CN customs code, e.g. `0702` | monthly import tonnes + origin countries |

Mappings are per species and apply to **every** country.

## A separate umbrella app — and its limits

Seasonality lives in its own umbrella app, `apps/mehungry_seasonality` (OTP app
`:mehungry_seasonality`, namespace `MehungrySeasonality`). Dependency direction:

```
mehungry_web  →  mehungry_seasonality  →  mehungry
```

The rules that keep it separate:

1. **One door in.** Code outside the app calls only the `MehungrySeasonality` facade.
2. **One door out.** The app touches the core app only through
   `MehungrySeasonality.Core` — the shared `Repo`, the shared `PubSub`, and
   **read-only** species access, handed on as slim `%{id, name, variety}` maps. No
   other file in the app references a `Mehungry.*` module.
3. **No changes to existing schemas.** Its crosswalk lives in its own table. Schemas
   reference a species by `foundemental_species_id` only — no `belongs_to` into the
   core schema.
4. **Own everything else**: config namespace (`config :mehungry_seasonality`), client
   seams, PubSub topic (`"seasonality_runs"`), Oban queue (`:seasonality`), tests.
5. **Enforced** by `MehungrySeasonality.BoundaryTest` (rule 2, and that core never
   mentions `MehungrySeasonality`). There is no other boundary tooling in the repo.

What is shared, by necessity: the one database, the one Oban instance and the one
PubSub server (the app has **no supervision tree** of its own), and the **migration
folder** — its tables are created by
`apps/mehungry/priv/repo/migrations/20261124120000_create_seasonality_tables.exs`
because `Mehungry.Repo` resolves migrations only from the core app's `priv/` and the
project has a single migration timeline. The `seasonality_` table prefix is the
boundary there.

This app is the model for carving out the next bounded context.

## Sources

| Signal | Source | Access | Licence / credit |
|---|---|---|---|
| Local | European Commission **agri-food data portal** — fruit & vegetable supply-chain prices | Open REST, no key | Commission open data — credit "European Commission, agri-food data portal" |
| Imports | **Eurostat Comext** monthly trade, dataset `DS-045409` | Open REST, no key | **CC BY 4.0** — credit "Eurostat" |

Both credits are shown on the admin page and must accompany any future public surface.

### Agri-food data portal (local signal)

```
GET https://api.tech.ec.europa.eu/agrifood/api/fruitAndVegetable/pricesSupplyChain
      ?memberStateCodes=EL&years=2023,2024,2025&products=Peaches
GET …/pricesSupplyChain/products          # the product names
GET …/pricesSupplyChain/productStages     # the four stages
```

Docs: <https://agridata.ec.europa.eu/extensions/DataPortal/API_Documentation.html>
(OpenAPI at `https://api.tech.ec.europa.eu/agrifood/v3/api-docs/fruit_and_vegetables`).
Parameters: `memberStateCodes`, `years`, `beginDate`, `endDate`, `productStages`,
`products`, `varieties`. A row looks like:

```json
{"memberStateCode":"EL","beginDate":"21/10/2024","endDate":"27/10/2024",
 "price":"€153.00","unit":"€/100Kg","periodType":"Week","period":43,"year":2024,
 "variety":"Peaches - All types and varieties",
 "productStage":"Ex-packaging station price","market":"National average (EL)"}
```

What we use: only *whether* a **producer-side** quote (`Farmgate price` or
`Ex-packaging station price`) exists in a period — never the price. Retail stages are
ignored (a retail quote says nothing about origin).

Quirks to know:

- Greece is **`EL`** here (ISO `GR`); `MehungrySeasonality.Countries` maps it.
- Rows carry a `variety`, not a product; a product is the prefix of the variety name.
- `periodType` is `Week` or `Month` (occasionally `Third`/`Year`, ignored). Dates are
  `DD/MM/YYYY`.
- No match returns **HTTP 404**, not an empty list (the client maps it to `[]`).
- The gateway occasionally answers with a transient "endpoint SUSPENDED" error; the
  Oban job simply retries.
- The older `/fruitAndVegetable/prices` endpoint and the `ec.europa.eu/agrifood` host
  were **decommissioned in October 2025** — use `api.tech.ec.europa.eu`.
- A quote means "domestic product is being traded". It cannot tell open-field harvest
  from greenhouse or cold storage.

Greek catalogue (products with a producer-side quote in 2025, months of the year
quoted): Apples, Bananas, Cucumbers, Egg Plants, Oranges, Pears, Tomatoes (12) ·
Lemons (11) · Kiwis Hayward (10) · Cauliflowers (8) · Melons (7) · Clementines,
Nectarines, Peaches, Table Grapes, Water Melons (6) · Apricots (4) · Mandarins (3).
That is 18 products — the ceiling of what the local signal can cover for Greece.

### Eurostat Comext (import signal)

```
GET https://ec.europa.eu/eurostat/api/comext/dissemination/statistics/1.0/data/DS-045409
      ?format=JSON&reporter=GR&product=0702&flow=1
      &indicators=QUANTITY_IN_100KG&freq=M
      &sinceTimePeriod=2023-01&untilTimePeriod=2025-12
```

`flow=1` is imports. Omitting `partner` returns every partner: individual origin
countries **and** aggregates (`WORLD`, `EXT_EU27_2020`, `INT_EU27_2020`, …). Both
intra-EU and extra-EU origins are included. The response is **JSON-stat**: a sparse
`value` object keyed by a row-major index over the dimensions in `id` with sizes
`size`. Quantities are in **100 kg**.

Quirks to know:

- Greece is **`GR`** here. `product` accepts HS2/HS4/HS6/CN8 codes (`0702` works).
- Partner codes are Comext's own: mostly ISO-2, plus e.g. `XS` Serbia, `XK` Kosovo,
  and `Q*` pseudo-countries (stores, confidential) which are dropped.
- A wrong parameter (e.g. `partner=WORLD` alongside a CN8 code that has no data)
  returns HTTP 200 with an empty `value` — not an error.

Common HS codes for the Greek catalogue (verify against the current Combined
Nomenclature before relying on them — only `0702`, `080810` and `080910` were
exercised against the live API):

| Food | HS | Food | HS |
|---|---|---|---|
| Tomatoes | `0702` | Oranges | `080510` |
| Cucumbers | `070700` | Mandarins | `080521` |
| Aubergines (Egg Plants) | `070930` | Clementines | `080522` |
| Cauliflowers | `070410` | Lemons | `080550` |
| Spinach | `070970` | Table grapes | `080610` |
| Apples | `080810` | Watermelons | `080711` |
| Pears | `080830` | Melons | `080719` |
| Apricots | `080910` | Kiwis | `081050` |
| Peaches + nectarines | `080930` | Bananas | `0803` |

### Verified against the live APIs (2026-11-24, Greece)

- **Tomatoes `0702`, 2024** — imports (t/month): 213 · 495 · 356 · 392 · 112 · 904 ·
  5,681 · 5,969 · **8,661** · 5,251 · 1,398 · 641; Turkey is the top origin
  (6,571 t in September). Recorded as the test fixture
  `test/fixtures/comext_gr_0702_2024.json`.
- **Apricots** (`Apricots` + `080910`, 2023–2025) — local `in_season` May–August;
  imports April–July (Spain first, then Romania/Bulgaria).
- **Apples** (`Apples` + `080810`) — quoted all 12 months → local `unresolved`;
  imports `major` in October–November, ~80 % from North Macedonia.

## Source research record

Everything evaluated before settling on the two sources above.

| Source | What it has | Verdict |
|---|---|---|
| **FAOSTAT** (QCL production, SUA/SCL, Food Balance Sheets) | Annual per-country production / supply / import totals | **Not seasonal** — annual only, 1–2 years behind. Fine for "supply per capita", useless for months. Its REST API now needs a login token (`faostatservices.fao.org` → 401; the old `fenixservices` host is down); the bulk CSV zips remain open. Already used elsewhere for `top_producers`. |
| **EC "fruit and vegetables calendar" page** | Prose lists by *season* for three climate zones | Too coarse: not per country, not per month, no import/storage, no data file. |
| **`gocemitevski/in-season`** | 62 products × climate zone, in-season months | GPL-3.0, no data licence, unsourced month windows; no import/storage. Rejected. |
| **`jansim/seasonal`** | Exactly this model (open field / under cover / heated / stored + monthly imports with origins) for DE, AT, BE, FR, GB | **No licence file**, no Greece. The *method* (national calendar for local + Comext for imports) is what this app follows; the data was not reused. |
| **`NunzioLangiulli/peak-season-database`** | 152 products, month scores for six European climate zones, storage info | CC BY 4.0 for its own work, but zone scores derive from EUFIC (non-commercial terms) and the Mediterranean zone is filled from Southern Italy. Not used. |
| **EUFIC seasonal map** | 24–30 countries by month | Terms forbid commercial use and modification; its single Greek source is a blog. Not usable. |
| **`seasoncalendar/seasoncalendar`** | 100+ foods, German-centric | Archived; availability data explicitly excluded from the GPL. Not usable. |
| **ADEME Impact CO₂** (France) | National in-season months, with an API | Licence Ouverte 2.0 — a usable *second local source* for France later. |
| **EU TAXUD weekly imports** (same portal, `/api/taxud/weeklyData/import`) | Weekly customs imports by member state, partner, CN8 | Extra-EU origins only, and no successful query was obtained. Comext is used instead. |
| **FAO Crop Calendar** | Planting/harvest periods | Client-side app; could not be assessed. |
| **US**: USDA ERS Food Availability, NASS Quick Stats, AMS Market News, Census monthly trade | Annual per-capita availability; production by state; daily market reports by origin; monthly imports | Not built. AMS Market News + Census trade are the candidates for a US version; neither was verified. |

Two findings that shaped the design:

1. **No source gives the label directly.** "Local vs imported per month" has to be
   derived from a local-activity signal plus a trade signal.
2. **Imports peak with the local season**, so the two facts are stored separately
   rather than as one exclusive status.

## Module map

`apps/mehungry_seasonality/lib/`

| File | Role |
|---|---|
| `mehungry_seasonality.ex` | **Facade** — the only door in |
| `mehungry_seasonality/core.ex` | **Adapter** — the only door out (Repo, PubSub, read-only species) |
| `countries.ex` | Known EU countries, per-source codes, which are enabled |
| `http.ex` | The one place HTTP happens (`get_json/1`, `:http_adapter` seam, 20 s timeout, no retries) |
| `agridata/{client_behaviour,client,parser}.ex` | Price-portal client + local-signal parsing |
| `comext/{client_behaviour,client,parser}.ex` | Comext client + JSON-stat import parsing |
| `schemas/{mapping,local_observation,import_observation,month_status,run}.ex` | The five schemas |
| `mappings.ex` | Crosswalk CRUD, name suggester, per-country product catalogue |
| `observations.ex` | Replace/read the raw fetched signals |
| `derivation.ex` | **Pure** rules: observations → 12 monthly statuses |
| `statuses.ex` | Re-derive, the admin grid, overrides |
| `fetcher.ex` | The unit of work: fetch + store + derive one species × country |
| `runs.ex` | Batch fan-out, run tracking, PubSub, cancel |
| `workers/fetch_worker.ex` | Oban worker on `:seasonality` |

### Facade (`MehungrySeasonality`)

| Function | Returns |
|---|---|
| `supported_countries/0`, `country_name/1` | enabled countries `%{code, name}` |
| `list_species/0` | every species as `%{id, name, variety}` |
| `list_mappings/0`, `save_mapping/1`, `delete_mapping/1` | crosswalk CRUD |
| `suggest_mappings/0` | `{:ok, %{species_id => %{product, score}}}` — portal product for each unmapped species |
| `available_products/1` | `{:ok, [%{product, months_quoted, suggested_species_id}]}` — the country's catalogue |
| `fetch_country/1` | `{:ok, batch_id}` or `{:error, :unsupported_country \| :already_running \| :no_mappings}` |
| `cancel_batch/1`, `latest_batch_id/1`, `list_batch_rows/1`, `counts_for_batch/1`, `batch_in_flight?/1`, `runs_topic/0` | run tracking |
| `grid/1` | per mapped species, 12 months of `%{status, local, import}` |
| `override_status/2`, `clear_override/1` | hand-set / release a month (`key = %{species_id, country, month}`) |
| `for_species/2` | `%{month => %MonthStatus{}}` — the read seam for a public surface |
| `available_species_ids/2` | `MapSet` of species ids locally on the market (`local` in `in_season`/`greenhouse`/`stored`/`unresolved`) in a country × month — what the core seam reads |
| `local_values/0`, `imported_values/0` | the allowed status values |

## Data model (`seasonality_*` tables)

| Table | Schema | Holds |
|---|---|---|
| `seasonality_mappings` | `Mapping` | species ↔ external product crosswalk; `source` `agridata` or `comext`, `external_code`, `label`. Unique on (species, source, code). |
| `seasonality_local_observations` | `LocalObservation` | raw local signal per species × country × month: `weeks_quoted`, `weeks_possible`, `years`, `retrieved_at` |
| `seasonality_import_observations` | `ImportObservation` | raw import signal: `tonnes_avg`, `origins` (`[%{"country", "share"}]`, top 5), `years`, `retrieved_at` |
| `seasonality_month_statuses` | `MonthStatus` | **the result**: `local`, `imported`, `top_origins`, `local_curated`, `imported_curated`, `note` |
| `seasonality_runs` | `Run` | per-species tracking row of a fetch batch: `batch_id`, `country`, `status`, `local_count`, `import_count`, `error`, `started_at`, `completed_at` |

All are keyed on `foundemental_species_id` (FK, `on_delete: :delete_all`) and, except
mappings, `country` (ISO-2) and `month` (1–12). Observations are **replaced wholesale**
per species × country on every fetch (delete + insert in one transaction), so removing
a mapping clears that source's data at the next fetch.

## Fetch → derive

```
admin "Fetch <country>"  ──▶  Runs.fetch_country/1   one pending Run per mapped species
                                     │                (one insert_all + one Oban.insert_all)
                                     ▼
                     Workers.FetchWorker  (queue :seasonality, 1 slot, max_attempts 3)
                                     │
                                     ▼
                     Fetcher.fetch_species/3
                       Agridata.Client.quotes/3 ─▶ Agridata.Parser.monthly/1 ─▶ Observations.replace_local/3
                       Comext.Client.monthly_imports/4 ─▶ Comext.Parser.monthly/1 ─▶ Observations.replace_imports/3
                                     │
                                     ▼
                     Statuses.rederive/2 ─▶ Derivation.derive/2 ─▶ seasonality_month_statuses
```

The window is the **three most recent complete calendar years**. A failing API call
raises, so the job retries; on the last attempt the species' run is marked `failed`
and the batch still finishes. Run tracking follows
[`oban_ui_connected_worker.md`](../reference_architecture/oban_ui_connected_worker.md)
(mirrors `Mehungry.Food.SpeciesEnrichmentRuns`): PubSub topic `"seasonality_runs"`,
messages `{:seasonality_processing, batch_id, species_id}` (slim, high-frequency) and
`{:seasonality_run, %Run{}}` (full row, terminal). One batch per country at a time;
`cancel_batch/1` cancels the remaining jobs and marks unfinished rows failed
("cancelled by admin") while keeping already-fetched data.

### Parsing

- **Local** (`Agridata.Parser.monthly/1`): distinct quoted weeks (by `beginDate`) per
  month from producer-side stages; a `Month`-period row marks the whole month.
  "Possible" weeks are the Mondays of that month, summed over the years that have any
  quote (so a year the country did not report does not drag every month down).
- **Catalogue** (`Agridata.Parser.months_by_product/2`): per product, in how many
  calendar months a producer-side quote exists; each row is attributed to the
  *longest* product name its `variety` starts with, which keeps
  `"Apples for processing"` apart from `"Apples"`. Processing and `Organic-` variants
  are then dropped.
- **Imports** (`Comext.Parser.monthly/1`): decodes the JSON-stat flat `value` index;
  monthly total = partner `WORLD`, in tonnes, averaged over the years with data;
  origins = individual 2-letter partner codes (aggregates and `Q*` pseudo-countries
  dropped), share ≥ 1 %, top 5. Several codes for one species are summed.

### Derivation rules (`MehungrySeasonality.Derivation`, pure)

| Fact | Value | When |
|---|---|---|
| `local` | `unknown` | no `agridata` mapping |
| | `in_season` | quoted in ≥ 50 % of the possible weeks |
| | `unresolved` | on the market in **all 12** months — greenhouse/storage cannot be told apart; an admin decides |
| | `none` | otherwise |
| | `greenhouse` / `stored` | only ever set by hand |
| `imported` | `unknown` | no `comext` mapping |
| | `none` | under 10 t/month on average |
| | `major` | ≥ 50 % of that product's own peak month |
| | `some` | otherwise |

Thresholds are module attributes in `derivation.ex` (`@local_share 0.5`,
`@import_floor_tonnes 10.0`, `@import_major_share 0.5`).

### Overrides

An admin can hand-set `local` and/or `imported` for a month (with a note). A hand-set
fact gets its `*_curated` flag and is **never overwritten** by re-derivation or a
re-fetch; leaving a fact on "Derived from data", or "Clear override", hands it back
and it is re-derived immediately from the stored observations.

## Core seam

The core app must never depend on this app, yet its meal planner needs seasons. So
**core owns the contract and this app implements it**:

```
core:  Mehungry.Food.SeasonalAvailability          (behaviour + dispatch, Noop default)
          ▲ implemented by, via config :mehungry, :seasonal_availability
app:   MehungrySeasonality.Core                     (the one door out)
          └─ MehungrySeasonality.available_species_ids/2 → Statuses
```

- **Callbacks:** `available_species_ids(country, month)` and
  `supported_countries/0`.
- **Core-side helpers:** `available_ingredient_ids/2` maps species to ingredients
  through `foundemental_foods`; `supported_country_codes/0` validates
  `user_profiles.country`.
- **Default:** without the config, or if the module isn't loaded, the `Noop`
  implementation answers "no seasons known, only Greece".
- **Boundary:** the implementation lives in `core.ex`, the one file allowed to name
  core, and the wiring lives in `config/config.exs`. Both `BoundaryTest` rules hold:
  only `core.ex` references `Mehungry.*`, and core's `lib/` never names this app.
- **"Available" is the effective value:** it means locally on the market, and an admin
  override counts (it is the stored `local`).
- **Consumer:** `Food.seasonal_fruit_ids/2` ([`food/snack_ingredients.md`](food/snack_ingredients.md)).

## Admin page

`/professional/seasonality` (`MehungryWeb.ProfessionalLive.SeasonalityLive`, admin
`:default2` session, "Seasonality" in the admin menu). It calls **only** the
`MehungrySeasonality` facade. A country switcher (`?country=GR`) sits above four
sections:

1. **Fetch** — "Fetch <country>" / "Cancel batch", progress counts, and a live
   per-species row stream (`start_async` enqueue, stream rows, 400 ms flush timer for
   the processing signal).
2. **Results** — species × 12 months. Each cell has a local band (green in season ·
   teal greenhouse · amber stored · pale yellow unresolved · grey none · white no
   source) over an import band (dark blue major · light blue some). Hover shows the
   numbers ("quoted 13 of 13 weeks", "172.4 t/month, from ES 63 %…"); a black dot
   marks a hand-set month. Click a cell to override or clear.
3. **Available foods without a mapping** — every portal product with a producer-side
   quote for the country last year that no species is mapped to yet, ordered by how
   many months of the year it is quoted in, badged **species exists** (best fuzzy
   name match, one-click Map) or **no species yet**. This is the worklist for deciding
   which species to create next (species are created in `/professional/usda-schema`).
   It needs two portal calls, so it loads with `start_async` after the page renders
   and offers "Try again" when the portal is down.
4. **Species mappings** — add/remove mappings, and "Run suggester", which
   fuzzy-matches unmapped species names to the portal's product list (Jaro ≥ 0.88
   after a crude singularisation — a hint to confirm). Comext codes are typed by hand.

## Configuration

```elixir
config :mehungry_seasonality,
  ecto_repos: [Mehungry.Repo],          # only so its `mix test` alias can migrate
  countries: ~w(GR CY IT ES DE)          # enabled countries; first is the default view
```

Adding a country is a config change (any EU member state listed in
`MehungrySeasonality.Countries`) plus a fetch.

Test seams (hand-written stubs via `Application.put_env`, the project's pattern — no
Mox): `:agridata_client`, `:comext_client`, and `:http_adapter` (a 3-arity fun
replacing `HTTPoison.get/3`).

## Wiring outside the app

The complete list of what the app required elsewhere:

| File | Change |
|---|---|
| `mix.exs` (root) | `mehungry_seasonality: :permanent` in the release `applications` |
| `apps/mehungry_web/mix.exs` | `{:mehungry_seasonality, in_umbrella: true}` |
| `config/config.exs` | `seasonality: 1` Oban queue (total slots 16 → **17**); the `config :mehungry_seasonality` block |
| `Dockerfile` | `COPY apps/mehungry_seasonality/mix.* …` before `deps.get` |
| `.dockerignore` | `apps/mehungry_seasonality/test` |
| `apps/mehungry/priv/repo/migrations/20261124120000_create_seasonality_tables.exs` | the five tables |
| `apps/mehungry_web/.../router.ex` | `live("/seasonality", ProfessionalLive.SeasonalityLive, :index)` |
| `apps/mehungry_web/.../views/layout/layout_view.ex` | the "Seasonality" admin menu link |
| `apps/mehungry_web/.../live/professional_live/seasonality_live.ex` | the admin page |
| `config/config.exs` | `config :mehungry, :seasonal_availability, MehungrySeasonality.Core` — the core seam ([Core seam](#core-seam)) |

Deployment: the migration runs with the normal release migrate step; no new
environment variables or secrets. Not yet exercised: `docker build` and a production
release with the new app.

## Runbook

1. Open `/professional/seasonality`, pick the country.
2. Read **Available foods without a mapping**. For a food badged "no species yet",
   create the species first; for "species exists", click **Map**.
3. Add the import code(s) in **Species mappings** (table of HS codes above).
4. **Fetch <country>** and watch the rows finish. Re-fetching is safe (idempotent).
5. Review the grid; resolve `unresolved` (all-year) species by hand as
   greenhouse/stored/in season per month.

Without the UI: `MehungrySeasonality.Fetcher.fetch_species(species_id, "GR")` runs one
species synchronously (used for the live verification above).

## Tests

- `mix test apps/mehungry_seasonality` — 40 tests (incl. `availability_test.exs`: the
  on-market rule, overrides, and core's seam reading through `Core`): both parsers against recorded live
  fixtures (`test/fixtures/`), the derivation rules, mappings + suggester + catalogue,
  fetch / overrides / run tracking / worker with stub clients
  (`test/support/seasonality_stubs.ex`, `seasonality_case.ex`), and the boundary guard.
- `mix test apps/mehungry_web/test/mehungry_web/live/professional_live/seasonality_live_test.exs`
  — 8 tests: admin gate, catalogue list + map, mappings, fetch to completion, overrides,
  per-country separation.

Run them from the **umbrella root**: running `mix` from inside `apps/mehungry_web`
fails on a `floki` `only: :test` mismatch with the core app that predates this work.

## Known limits

- **Coverage is bounded by the portal**: 18 products for Greece. Everything else has
  no local signal and can only show imports.
- **"On the market" is not "in the field"**: year-round products read `unresolved`
  until an admin sets greenhouse/stored months by hand.
- **`major` imports are relative to the product's own peak month**, not to local
  supply — there is no monthly local volume to compare with.
- **Species must already exist**; the app never creates them. A dev database with few
  species shows few rows.
- **Comext codes are typed by hand** and are not validated against the nomenclature
  beyond "2–8 digits".
- **Suggester is name-based** (English names), so a species named differently from
  the portal product needs a manual mapping.
- **One year for the catalogue** (last complete year) vs three for the fetch.
- The admin page has LiveView test coverage but has not been visually reviewed.

## Not built yet

(Meal planning reads seasons through the core seam since 2026-11-24.) A public `/foods` surface and `/api/v1` fields · the US (candidate sources: USDA AMS
Market News, US Census monthly trade) · national harvest calendars as a second local
source (France's ADEME data is the one clearly open) · a bundled "portal product →
HS code" seed list so imports are suggested too · scheduled re-fetches.
