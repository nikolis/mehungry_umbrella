# Chemistry context

`Mehungry.Chemistry` is the external chemical-data **enrichment layer** for the
canonical bioactive-compound registry (`Mehungry.Food.Compounds`).

It treats PubChem as an external authority in exactly the way USDA is an external
authority for ingredients: an importer normalizes a fuzzy compound name into a
stable chemical identity and **syncs it into `Food.Compounds`**. The rest of the
application never talks to PubChem — it only reads `Food.Compounds`.

```
        USDA  ──▶ canonical ingredient registry   (Food.Ingredients)
        PubChem ─▶ canonical compound registry     (Food.Compounds)   ← this doc
```

---

## 1. Why this exists

`Food.Compounds` rows carry a canonical `name`, `synonyms`, structural
`properties`, and — in the normalized `compound_identifiers` table — their
cross-database identity (MeSH, PubChem CID, ChEBI, CAS, HMDB, InChIKey). But
historically these were filled only manually or by `literature`/`ai` sources, and
there was no automated way to turn a fuzzy input name — `"oxalate"`, `"oxalic
acid"`, `"ethanedioic acid"` — into a single stable identity:

> PubChem **CID** `971`, canonical name `Oxalic acid`, molecular formula
> `C2H2O4`, SMILES, InChI, InChIKey, ChEBI `CHEBI:16995`, synonyms.

This layer adds that, as an **importer/adapter**, not a data store.

**Boundaries honored:**

- The `compounds` table is **not altered**; the registry stays in `Food.Compounds`
  (it is ingredient-coupled via `IngredientCompoundRelationship`).
- PubChem is not hard-coded as the only authority — provenance lives in a
  `compound_sources` layer so FooDB / ChEBI / HMDB slot in later with no schema
  change.
- The full raw API payload is never lost — every response is stored append-only.
- Compounds are **not versioned** (CIDs are stable); history/versioning stays on
  the relationship/assertion layer.

---

## 2. Architecture

```
        PubChem PUG REST  (external authority)
                 │
                 ▼
  Chemistry.PubChem  (importer / enrichment adapter — never queried by the app)
        ├── normalize ─────────▶ Food.Compounds            (canonical registry)
        │                          └─ compound_sources      (per-source provenance)
        └── raw payload ───────▶ pubchem_responses          (append-only cache)
```

### `pubchem_responses` — raw API cache (append-only)
One row per successful PUG REST fetch; never overwritten. Gives us
reproducibility, debugging, re-import, and resilience against PubChem schema
changes — if we later need a field we don't currently extract, we backfill it
from `raw_json` instead of re-hitting the API.

| Column | Meaning |
|---|---|
| `endpoint` | `name_cids \| properties \| synonyms` — which PUG call. |
| `requested_name` | Input name, for `name_cids` lookups. |
| `cid` | Resolved/queried CID (nil for a name that matched nothing). |
| `raw_json` | Full decoded payload. |
| `etag` / `api_version` | Response headers, when present. |
| `retrieved_at` | Fetch time. |

Also serves as the **durable** name→CID cache: `latest_resolved_cid/1` reads the
newest `name_cids` row for a name.

### `compound_sources` — per-source provenance
One row per `(compound, source_type)` — an idempotent upsert on re-sync.

| Column | Meaning |
|---|---|
| `compound_id` | FK → `compounds`. |
| `source_type` | `pubchem \| chebi \| hmdb \| foodb`. |
| `external_identifier` | e.g. `"971"`, `"CHEBI:16995"`. |
| `last_synced_at` | Last successful sync time. |
| `raw_response_id` | FK → the exact `pubchem_responses` payload the sync used. |

---

## 3. The resolver (`Mehungry.Chemistry.Resolver`)

The single, **identifier-first** entry point for ingestion. Sources (PubTator,
literature, manual) call the resolver rather than PubChem directly.

```elixir
# Identifier-first: a MeSH id carried by a PubTator annotation.
Mehungry.Chemistry.resolve(%{namespace: "mesh", identifier: "D000082", name: "Oxalic acid"})
#=> {:ok, %Mehungry.Food.Compound{name: "Oxalic acid", ...}}

# Name-only fallback (a source with no normalized identifier).
Mehungry.Chemistry.import_compound("oxalate")   #=> {:ok, %Compound{...}}
Mehungry.Chemistry.import_compound("nonsense")  #=> {:error, :not_found}
```

Options: `:compound_type` (default `"other"`, never overwrites an existing type),
`:source` (who asserted the seeding identifier), `:refresh`.

Flow (idempotent, cached, history-preserving):

```
resolve(input)
 ├─ identifier given → Food.get_compound_by_identifier(ns, id)  → hit returns it
 └─ resolve anchoring CID
     ├─ seed already in pubchem namespace → that IS the CID
     └─ else name → :pubchem_cache → pubchem_responses ledger → Client.name_to_cids
         no CID and no seed → {:error, :not_found}
     ├─ compound already anchored (seed id / CID) and not :refresh
     │     → attach the new seed id if any (no HTTP) → return it
     └─ else Client.properties/1 + synonyms/1 (store raw)
             → Food.upsert_compound (name, synonyms, structural properties)
             → Food.upsert_compound_identifier per namespace
                 (seed id is_primary; pubchem/chebi/cas/inchikey cross-refs)
             → record compound_sources[pubchem]
```

**Identifiers, not names, are the currency.** Lookup/dedup is by `(namespace,
identifier)`. `"oxalate"`, `"oxalic acid"`, and `"ethanedioic acid"` all resolve to
CID `971` and converge to a **single** `compounds` row; a MeSH id and a name-only
import of the same molecule converge too.

**Identifiers vs. descriptors.** Globally-unique cross-database identities (MeSH,
PubChem CID, ChEBI, CAS, InChIKey) are rows in `compound_identifiers`. Structural
*descriptors* that are not unique identifiers (molecular formula, SMILES, IUPAC
name, InChI — isomers share a formula) live in the compound's `properties` jsonb.
The complete PubChem payload always lives in `pubchem_responses`.

`name_to_cids/1` is used only to cross-reference a CID (and as the anchor for a
name-only source), never as the primary identity key.

---

## 4. HTTP client (`Mehungry.Chemistry.PubChem.Client`)

A PUG REST client modeled on `Mehungry.FoodData.Usda.FdcHttp`:

- bounded exponential-backoff retry on network errors, 5xx, and `503` throttles
  with a short `Retry-After`;
- a hard throttle surfaces as `{:error, {:rate_limited, seconds}}`;
- `404` / no-CID maps to `{:error, :not_found}`;
- enforces PubChem's published **5 req/s** ceiling via `Mehungry.RateLimit`.

Config seams:

| Key | Default | Purpose |
|---|---|---|
| `:pubchem_http_adapter` | `&HTTPoison.get/3` | HTTP call; stubbed in tests. |
| `:pubchem_base_url` | `https://pubchem.ncbi.nlm.nih.gov/rest/pug` | API root. |
| `:pubchem_rate_limit` | `5` | Local req/s ceiling (lifted in tests). |

The hot name→CID cache is the `:pubchem_cache` Cachex instance started in
`Mehungry.Application`.

---

## 5. Module map

| Module | File | Role |
|---|---|---|
| `Chemistry` | `chemistry.ex` | Context: `resolve`/`import_compound` entry, raw-response cache, provenance CRUD. |
| `Chemistry.Resolver` | `chemistry/resolver.ex` | Identifier-first resolver — the single ingestion entry point. |
| `Chemistry.PubChem` | `chemistry/pubchem.ex` | Name-only fallback (delegates to the resolver). |
| `Chemistry.PubChem.Client` | `chemistry/pubchem/client.ex` | PUG REST HTTP client (retry + rate limit). |
| `Chemistry.PubChem.RawResponse` | `chemistry/pubchem/raw_response.ex` | Append-only raw-payload schema. |
| `Chemistry.CompoundSource` | `chemistry/compound_source.ex` | Per-source provenance schema. |
| `Food.CompoundIdentifier` | `food/schemas/compound_identifier.ex` | Normalized `(namespace, identifier)` identity row. |
| `Food.Compounds.get_compound_by_identifier/2` · `upsert_compound_identifier/1` | `food/compounds.ex` | Identifier lookup + the write path the resolver uses. |

---

## 6. Testing

```bash
mix test apps/mehungry/test/mehungry/chemistry/pubchem/client_test.exs \
         apps/mehungry/test/mehungry/chemistry/pubchem_test.exs
```

- `client_test.exs` — parse of each endpoint, `404`/no-CID → `:not_found`, `503`
  retry-then-succeed, persistent `503` → `{:error, {:rate_limited, _}}`,
  `etag`/`api_version` in meta. Fully offline via the `:pubchem_http_adapter` stub.
- `pubchem_test.exs` — the three-names-converge-to-one-CID example, idempotent
  re-import (zero HTTP), raw-payload storage, provenance recording, `:not_found`
  + negative caching, and `compound_type` default/override.

---

## 7. Out of scope / follow-ons

- No Oban batch pipeline — resolution is synchronous; callers batch it themselves.
- Additional sources (FooDB, ChEBI, HMDB, Phenol-Explorer) reuse `compound_sources`
  and the `upsert_compound_by_cid/1` seam.
