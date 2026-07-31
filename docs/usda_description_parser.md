# USDA Description Parser

Deterministic, rule-based parsing of USDA food descriptions into canonical
structured foods. No AI, no network — pure functions over a DB-backed
vocabulary.

> Related: `docs/schema_discovery.md` is an offline read-only diagnostic that
> regex-mines the raw `ingredients.name` corpus to flag dimensions this parser
> does **not** yet capture (candidate new columns). It measures; it does not
> parse.

```
"Pickles, cucumber, dill or kosher dill"
        │
        ▼  Tokenizer        comma → segments; " or "/" and "/";" → phrases; "(…)" lifted
[["Pickles"], ["cucumber"], ["dill", "kosher dill"]]
        │
        ▼  Normalizer       downcase · strip punctuation · singularize last word
[["pickle"], ["cucumber"], ["dill", "kosher dill"]]
        │
        ▼  Classifier       vocabulary lookup, longest match first
[processing "pickled" (head, implies cucumber), food "cucumber", modifier ×2]
        │
        ▼  RuleEngine       ordered fold of single-purpose rules
%Result{canonical_food: "cucumber", harvest_stage: :mature, processing: [:pickled],
        processing_modifiers: ["dill", "kosher dill"], packaging: :na,
        part: nil, dismemberment: nil, confidence: 1.0}
```

Meat/dairy descriptions carry more fields: `part` (USDA primal/body-part —
"loin"), `dismemberment` (the specific retail cut — "t bone steak"),
`bone_state` ("boneless"), `portion` (a **list** of tissue/skin selections —
"separable lean only", "skinless"), `grade` (USDA quality grade — "choice"),
and `fat` (fat content or trim — "3.25% milkfat", "85% lean 15% fat",
"trimmed to 1/8 fat"). All are `nil`/`[]` for anything that doesn't carry them:

```
"Beef, loin, top loin steak, boneless, separable lean only, trimmed to 1/8\" fat, choice, raw"
        ▼
%Result{canonical_food: "beef", part: "loin", dismemberment: "top loin steak",
        bone_state: "boneless", portion: ["separable lean only"], grade: "choice",
        fat: "trimmed to 1/8 fat", processing: [:raw]}
```

Not to be confused with `Mehungry.FoodData.Usda.FoodParser`, which ingests FDC
JSON payloads into `ingredients` rows. This parser (`…Usda.Parser.*`) reads the
*description string* of such a row and infers semantics: "Pickles" is not a
food (it is pickled cucumber), "Oil, corn" is corn processed into oil, never a
food called "oil".

## Module responsibilities

All under `apps/mehungry/lib/mehungry/food_data/usda/parser/`
(`Mehungry.FoodData.Usda.Parser.*`):

| Module | Responsibility |
|---|---|
| `Pipeline` | Entry point `parse/2`; carries `@parser_version` (`version/0`) |
| `Tokenizer` | Raw text → segments of phrases; splits phrases on ` or `/`;`/` with ` (**not** ` and `, which binds single qualifiers like "separable lean and fat") |
| `Normalizer` | Canonical form: downcase, strip, singularize (`"Carrots"` → `"carrot"`); keeps `%`,`.`,`/` so fat numerics survive |
| `Vocabulary` | In-memory alias dictionary, `:persistent_term`-cached; `build/2` for DB-free tests |
| `Classifier` | Phrase → typed `Token` (food/processing/harvest_stage/part/dismemberment/bone_state/portion/grade/prepared/modifier/packaging/not_food/unknown); longest-match-first; unknowns penalize confidence |
| `RuleEngine` | Ordered fold of rules; `{:halt, %Skipped{}}` short-circuits |
| `Result` / `Skipped` / `Token` | The accumulator structs |
| `Rules.*` | One semantic transformation each (below) |

Persistence and review live under `Mehungry.Food` (facade `defdelegate`s on
`food.ex`):

- `Food.ParserVocabulary` — vocabulary CRUD + `dump/0`; every mutation reloads
  the `Vocabulary` cache.
- `Food.ParsedFoods` — parses stored as append-only candidates in
  `ingredient_parsed_foods` (find-or-create on `(ingredient_id,
  parser_version)`); admin edit (`update_parsed_candidate/2`), verify/reject
  with supersede-not-delete history, review queries, batch enqueue.
- `Food.FoodParsingRuns` — run lifecycle + PubSub progress
  (`{:food_parsing_run, run}` on `"food_parsing_runs"`).
- `Mehungry.ObanWorkers.IngredientFoodParsingWorker` — batches of 100 on the
  `:imports` queue, self-re-enqueueing until every fdc-backed ingredient has a
  row at the current parser version (the row itself is the termination
  ledger — Skipped included).

## The rule engine

`RuleEngine.rules/0` =
`@default_rules ++ Application.get_env(:mehungry, :usda_parser_extra_rules, []) ++ @tail_rules`.

Order is load-bearing: template rules consume their tokens before
`FoodHeadRule` resolves the food; the two tail sweeps always run last.

| Rule | Transformation |
|---|---|
| `NotFoodRule` | `:not_food` token → halt with `%Skipped{reason: :not_food}` |
| `PreparedDishRule` | `:prepared` marker (commercial/homemade/fast food…) → halt `%Skipped{reason: :prepared_dish}` (marker heuristic for out-of-grammar composite dishes) |
| `OilRule` | Head template `"Oil, <ingredient>"` → processing `:oil`, food ← next food token |
| `PickleRule` | Head `"Pickles, …"` → `:pickled`; explicit food wins, else implied cucumber (×0.9) |
| `JuiceRule`, `RawRule`, `RoastedRule`, `BoiledRule`, `FrozenRule`, `DriedRule`, `PureeRule` | 3-line `use Rules.ProcessingMethodRule, method: :x` claims |
| `FoodHeadRule` | First unconsumed food token wins; none at all → head phrase as free text (×0.5) |
| `BabyRule` | `:harvest_stage` "baby" → `harvest_stage: :baby` (default `:mature`) |
| `PartRule` | First unconsumed `:part` token → `result.part` (generic — any vocabulary part, default `nil`) |
| `DismembermentRule` | First unconsumed `:dismemberment` token → `result.dismemberment` (generic, default `nil`) |
| `BoneStateRule` | First `:bone_state` token → `result.bone_state` (default `nil`) |
| `PortionRule` | Sweeps every `:portion` token → `result.portion` list (reading order, default `[]`) |
| `GradeRule` | First `:grade` token → `result.grade` (default `nil`) |
| `FatRule` | Pattern rule: regex-scans segments for fat content/ratio/trim → `result.fat` (default `nil`); consumes the matched segment's unknowns. Bare word-forms ("whole"/"lowfat") excluded — "whole" is ambiguous |
| `SeedRule`, `LeafRule`, `FruitRule` | `use Rules.DescriptorModifierRule, word: "x"` — plant parts → modifiers |
| `CannedRule` | `use Rules.PackagingRule, type: :canned` |
| `ModifierRule` (tail) | Sweeps leftover modifiers + qualifier-segment unknowns into `processing_modifiers` |
| `FinalizeRule` (tail) | Dedupe, reading-order modifiers, clamp+round confidence; safety-sweeps unclaimed `:processing` tokens so DB-only methods are never lost |

**Idempotence contract** (`Rules.Rule` behaviour): a rule acts only on tokens
with `consumed: false`, marks everything it touches consumed, and appends via
`Helpers.append_unique/2` — applying any rule twice is a no-op.

## Confidence

Start 1.0, multiplicative penalties, `FinalizeRule` clamps to [0.0, 1.0] and
rounds to 3 decimals:

| Anomaly | Factor | Applied by |
|---|---|---|
| Unknown token | ×0.8 each | Classifier |
| Food inferred from `implied_food` (bare "Pickles") | ×0.9 | PickleRule |
| No food token at all — free-text head fallback | ×0.5 | FoodHeadRule |

`"Frobnitz, canned"` → 0.8 (unknown "frobnitz") × 0.5 (fallback) = **0.4**.
Skips are exact vocabulary hits: confidence 1.0.

Note: a `fat` value is still extracted even though the words that form it
("3.25%", "milkfat") are unknown and lower confidence — and un-vocabularied
qualifiers (fortification, variety/cultivar names) do the same. That low
confidence is intended review signal, not a parse failure; the structured
fields are populated regardless.

## Vocabulary tables

All aliases are stored pre-normalized (changesets pipe through
`Parser.Normalizer.normalize/1`), each with a unique index:

- `canonical_foods` + `canonical_food_aliases` — the canonical-food lexicon
  (distinct from `ingredients`); grows through seeds *and* through review
  (verifying a parse find-or-creates its food).
- `parser_processing_methods` + `parser_processing_aliases`
  (`head_template`, `implied_canonical_food_id` encode "pickle" → pickled +
  cucumber, "oil" head).
- `parser_harvest_stages` + `parser_harvest_stage_aliases`.
- `parser_parts` + `parser_part_aliases` — primal/body-part descriptors
  ("loin", "chuck").
- `parser_dismemberments` + `parser_dismemberment_aliases` — specific retail
  cuts ("t bone steak").
- `parser_packaging_aliases` (`"jarred"` → canned).
- `parser_descriptor_aliases` — `kind: not_food | modifier | noise | bone_state
  | portion | grade | prepared`. The last four are small closed enumerations
  that ride the existing descriptor table (no dedicated tables, unlike
  parts/dismemberments): bone_state ("boneless"), portion ("meat only",
  "skinless", "separable lean and fat"), grade ("choice"), prepared
  ("commercial" → skip).

`Parser.Vocabulary` caches the merged dictionary in `:persistent_term`
(zero-copy reads on every parse; writes only at admin-edit/seed frequency).
Every `Food.ParserVocabulary` mutation and the seeder end with
`Vocabulary.reload/0`.

## How to add …

**A processing type ("smoked")** — no existing parser file changes:

1. `defmodule Mehungry.FoodData.Usda.Parser.Rules.SmokedRule do
   use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :smoked end`
2. `config :mehungry, :usda_parser_extra_rules, [.…Rules.SmokedRule]`
3. Rows: `Food.ParserVocabulary.add_processing_method("smoked")` +
   `add_processing_alias(id, %{alias: "smoked"})` (or seed rows).

(Without the rule module, `FinalizeRule`'s safety sweep still records the
method from DB rows alone — the dedicated rule is preferred because it
controls list ordering.)

**A food** — `Food.ParserVocabulary.create_canonical_food(%{name: "kohlrabi"})`;
it is also created automatically when an admin verifies a parse whose food
text is new.

**A synonym** — `add_food_alias(food_id, "german turnip")`. Same for
harvest-stage/part/dismemberment/packaging/descriptor aliases. All reload the
cache.

**A part or dismemberment** ("shank", "drumstick") — no rule changes needed,
`PartRule`/`DismembermentRule` are already generic:
`Food.ParserVocabulary.add_part("shank")` + `add_part_alias(id, "shank")` (or
`add_dismemberment/1` + `add_dismemberment_alias/2`).

**A bone-state / portion / grade / prepared marker** — no rule changes needed
(the rules are generic over their token type):
`add_descriptor_alias(%{alias: "shank bone", kind: "bone_state"})`,
`kind: "portion"` ("meat and bone"), `kind: "grade"` ("no grade"),
`kind: "prepared"` ("meal kit" → skip).

**A fat pattern** — `FatRule` is regex-based, not vocabulary. Extend
`@patterns` in `rules/fat_rule.ex` for a new numeric shape.

**A not-food marker** — `add_descriptor_alias(%{alias: "pet food", kind: "not_food"})`.

Seeds: `Mehungry.Food.ParserVocabularySeeder.seed/0` (idempotent, called from
`priv/repo/seeds.exs`).

## Versioning & re-parsing

Every stored parse carries `parser_version` (= `Pipeline.version/0`, currently
`1.1.0` — bumped from `1.0.0` when the bone_state/portion/grade/fat fields, the
`and`/`with` tokenizer change and the prepared-dish skip landed), and rows are
unique on `(ingredient_id, parser_version)`. Bump the version after changing
rules or vocabulary semantics: the next batch run re-parses the whole corpus as
fresh candidates (the parser is deterministic, so same-version re-runs are
no-ops). Verifying a new-version parse supersedes the previously
verified one (`superseded_by_id` chain — never deleted); the review queue only
shows current-version candidates.

## Admin UI & API

- `/professional/science` — "Description parsing" stage card (Run button +
  live progress via `FoodParsingRuns` broadcasts).
- `/professional/science/parse-review` —
  `MehungryWeb.ProfessionalLive.ParseReviewComponent`: pending parses
  (lowest confidence first) with inline Edit → Verify/Reject, plus the
  read-only Skipped section and per-row trace toggle.
- `POST /api/parser/parse` `{"description": "Oil, corn", "trace": true}` —
  stateless JSON parse (`MehungryWeb.Api.ParserController`).

## Tracing

`Pipeline.parse(text, trace: true)` accumulates JSON-safe per-stage entries
(tokenizer/normalizer output, classified tokens, each rule's action and every
confidence penalty). The batch worker persists it to the `trace` jsonb column;
the review UI renders it behind a `<details>` toggle. Default off (`trace:
nil`) — zero cost.
