# Schema Discovery

A **read-only diagnostic** that mines the USDA `ingredients.name` corpus with
regexes to see which structured dimensions the names actually carry, how much of
the corpus each covers, which the deterministic parser already extracts, and
which genuinely-un-captured dimensions would be worth adding as new
`ingredient_parsed_foods` columns. It reads ingredients and proposes SQL — it
never runs a migration or mutates anything.

> Example: 40% of names carry a **size** token (large/medium/small/…) but there
> is no `size` column, so the report proposes one; the 55% that carry a **grade**
> token are reported for QA only, since the parser already fills the `grade`
> column.

```
   ingredients.name ── regex mine ──▶ per-dimension coverage ──▶ report        ← this doc
   (raw USDA strings)   (PureEx,        (union of matched          (Coverage:
                         one regex set)   ingredient ids)            fill-rate,
                                                                     proposals,
                                                                     summary)
```

This is diagnostic tooling *adjacent to* the shipped parser in
`docs/usda_description_parser.md`. That pipeline is the real extractor
(curated vocabulary + rules → structured columns); this layer only measures the
name corpus and flags gaps. The two must not be confused: Schema Discovery
reports (does not re-add) the dimensions the parser already captures.

---

## 1. Why this exists / status

The parser writes ten structured columns on `ingredient_parsed_foods`
(`grade`, `part`, `bone_state`, `harvest_stage`, `processing`, `packaging`,
`fat`, …). Schema Discovery answers a different, offline question: *"Across all
raw ingredient names, which recurring dimensions are present, and are any of them
not yet captured?"* — a coverage/QA signal for evolving the parser schema.

**Boundaries honored:**

- **Read-only.** Emits `ALTER TABLE … ADD COLUMN` text; never executes it.
- **Deduped against reality.** Every mined dimension maps to the existing
  `ingredient_parsed_foods` column that captures it (or `nil`). Migrations are
  proposed **only** for `nil` (un-captured) dimensions — realistically
  `variety`, `size`, `origin`.
- **Union, not sum.** One name matches many dimensions, so coverage is computed
  over the union of matched ingredient ids, never a sum of per-dimension
  fractions (which overshoots and can exceed 100%).
- **No advice, no writes.** Adopting a proposed column (adding the migration +
  parser rule/vocabulary) is a separate, deliberate decision.

## 2. The single regex set (`PureEx`)

`Mehungry.Food.SchemaDiscovery.PureEx` is the source of truth. Its `@patterns`
keyword list maps each dimension to `%{regex, mode, column}`:

- `regex` — a `\b`-anchored alternation (word boundaries stop `select` matching
  inside `selected`, etc.).
- `mode` — `:scan` (all matches per name, downcased + de-duped) or `:capture`
  (first capture group, for `trimmed to <X>`).
- `column` — the `ingredient_parsed_foods` column that already captures the
  dimension, or `nil` if un-captured.

`analyze/0` returns `total_ingredients`, a `patterns` map, and
`recommendations` — one map per dimension with ≥5 distinct values, carrying
`coverage` (distinct matched ingredients ÷ total), `matched_ids`,
`existing_column`, `new_column?`, `top_values`, and a `priority` label.
`patterns/0` exposes the raw config for callers (e.g. tests).

## 3. The report (`Coverage`)

`Mehungry.Food.SchemaDiscovery.Coverage.recommend/1` (default target `0.95`):

- Greedily selects the minimal set of dimensions whose **union** of matched
  ingredients reaches the target (`find_minimal_set/3`, picking the dimension
  that adds the most new ids each step).
- `migration_sql` — `ADD COLUMN` + index for the selected dimensions where
  `new_column? == true` only.
- `parse_fill_rate/0` — a **separate** metric: fraction of ingredients with a
  linked `canonical_food`. Reported alongside but never conflated with dimension
  coverage.

## 4. Optional semantic layer (`Hybrid`)

`Hybrid.discover/0` layers embedding-based clustering on top of `PureEx`: it
finds low-confidence / unmatched parses, and — only when `:enable_embeddings` is
on — embeds their names via `Mehungry.Food.Parser.Embedder` (the parser-side
delegator over the shared `AI.EmbeddingServer` serving), clusters by cosine
similarity (single-link, 0.8 cutoff), and suggests a field per cluster. Off by
default; the admin page shows these clusters only when embeddings are enabled.

`cluster_embeddings/1` returns **one cluster id per input embedding, in input
order**, so `group_by_semantics/1` can zip each ingredient to its cluster. (An
earlier version returned one id per *cluster*, making the zip positional and
collapsing everything into singletons — regression-guarded in
`schema_discovery_hybrid_test.exs`.) The admin page's **Min size** buttons
(`All`, `> 1`, `> 2`, …) filter out small clusters for display only — a cut over
the already-computed groups, so it never re-embeds.

`Fallback.discover/0` is a lighter, flat summary that reuses the same `PureEx`
regex set (no embeddings needed).

## 5. Admin view

`/professional/schema-discovery`
(`MehungryWeb.ProfessionalLive.SchemaDiscovery`, admin-gated `:default2`
session). Read-only: computes the report once on mount and on an explicit
**Recompute** click (the scan touches every ingredient, so never on a timer).
Renders the parse fill-rate, a per-dimension table (coverage · captured?/column ·
top values · priority), the proposed migrations (new columns only), and — when
embeddings are enabled — the semantic outlier clusters.

## 6. Module map

| Module | Role |
|---|---|
| `SchemaDiscovery.PureEx` | Single regex set; `analyze/0`, `patterns/0` |
| `SchemaDiscovery.Coverage` | `recommend/1` report, union math, `parse_fill_rate/0`, migration text |
| `SchemaDiscovery.Fallback` | Flat embeddings-free summary reusing `PureEx` |
| `SchemaDiscovery.Hybrid` | Optional embedding clustering over `PureEx` |
| `MehungryWeb.ProfessionalLive.SchemaDiscovery` | Admin page |

## 7. Testing

`apps/mehungry/test/mehungry/food/schema_discovery_test.exs` seeds ingredients
whose names match both an existing-column dimension (`grade`) and an un-captured
one (`size`), then asserts: existing dimensions are flagged
`new_column?: false` with the right `existing_column`; the tightened regex
rejects `selected` as a grade; coverage is the union (6) not the sum (12); and
migrations propose only un-captured columns. Assertions are scoped to the seeded
ids so pre-seeded test data is irrelevant.

## 8. Out of scope

- Executing migrations or adding parser rules/vocabulary for a proposed
  dimension — proposal only.
- Replacing the deterministic parser (`docs/usda_description_parser.md`) — this
  layer measures the name corpus, it does not parse.
