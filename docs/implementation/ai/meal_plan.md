# Meal-Plan Generation

AI meal-plan generation is one of the app's flagship user-facing features: from a
short free-text brief (or a structured blueprint), it produces a **7-day plan** —
five slots a day, drawn from the user's own recipe catalog plus whole-food
ingredients — and drops it onto the calendar or stores it as a reusable plan.

This doc has two parts:

1. **[How the feature works](#part-1--how-the-feature-works)** — the production
   pipeline: surfaces, the agent, generation → persistence, and its dependencies.
2. **[Evaluation](#part-2--evaluation)** — the harness that measures whether the
   generated plans are actually *good*, and the latest results.

---

# Part 1 — How the feature works

## What it produces

A plan is **7 days × 5 slots** = 35 entries. The five slots per day are
**Breakfast, Morning Snack, Lunch, Afternoon Snack, Dinner**
(`Mehungry.History.MealType`). Each entry is **either**:

- a **recipe** (`recipe_id` + `cooking_portions`), or
- a single **whole-food ingredient** (`ingredient_id` + `quantity` + unit) —
  snacks and light sides are usually an ingredient.

The agent returns *normalized, calendar-independent* entries (relative
`day_index` 1..7 + canonical `meal_type`, see `MealPlanAgent.normalize_entry/2`),
so the same output can land on the calendar **or** be stored as a standalone plan.

## Where users trigger it

Three surfaces, all funnelling through the same core (`Mehungry.AI.MealPlanGenerator`):

| Surface | Entry point | What happens with the plan |
|---|---|---|
| **Calendar** | `CalendarLive.Index` → `MealPlanGenerator.run/5` | Materialized onto the week's calendar dates as `UserMeal`s |
| **Meal Blueprints** | `MealBlueprintLive.Index` → `MealPlanGenerator.generate_entries/5` → `MealBlueprints.store_plan_meals/2` | Stored as independent `BlueprintPlanMeal` rows (not the calendar) |
| **Mobile REST API** | `MehungryWeb.Api.MealPlanWorker` (async Oban job) → `MealPlanGenerator.run/5` | Same calendar materialization, driven from the React Native client |

Generation is **quota-gated** by subscription tier (`Subscriptions.check_quota/2`
before, `record_usage/2` after success): free `0`, `m3hungry_plus` `4`/mo,
`pro` `10`/mo. The owner email bypasses quotas.

## The agent (`Mehungry.AI.Agents.MealPlanAgent`)

The planner is a **history-aware tool-use loop** built on `AI.Agent`, running on
**Haiku 4.5** (`claude-haiku-4-5-20251001`) — cheap, fast structured tool calling.
`run/5` threads a pure accumulator (no process state) and returns `{:ok, entries}`
or `{:error, reason}`. Config: `max_tokens: 4096`, `max_iterations: 14`,
telemetry-tagged `agent: "meal_plan"`.

### Tools the model is given

| Tool | Purpose |
|---|---|
| `get_recent_meals` | Last 21 days of the user's meal history, so the plan avoids repeating what they just ate |
| `search_catalog` | Semantic search of the user's recipe catalog by natural-language query (`RecipeVectorSearch`) — returns `recipe_id`, title, difficulty, servings |
| `search_ingredients` | Whole-food ingredient search (fruit, nuts, cheese, yogurt…) for snacks/sides, with unit options |
| `submit_plan` | Validate + accept the complete 35-entry plan; the **only** way to finish |

### The invariants it enforces

The DB is the source of truth; the model is never trusted blindly
(`docs/ai/ai.md` → "Validate, don't trust"). `submit_plan` rejects and makes the
model retry when:

- **Provenance:** a `recipe_id`/`ingredient_id` the search tools never surfaced
  this run (the dominant hallucination mode) — steers the model back to search.
- **Shape:** an entry with both a recipe *and* an ingredient, or neither; a bad
  date/slot; a duplicate (day, slot); a non-positive ingredient quantity.
- **Avoid-foods** (e.g. Low-FODMAP): terms from the blueprint's `avoid_foods` are
  filtered out of search results *before* the model sees them (so a filtered id
  never enters the provenance set) **and** forbidden in the prompt. Belt and
  suspenders. `avoid_terms/1`, `reject_avoided/3`. This is the **specific-food**
  layer (onion, garlic, honey) — literal substring matching.
- **Diet (vegan/vegetarian/pescatarian)**: a separate **category** layer.
  `search_catalog` keeps only diet-compatible recipes and `search_ingredients`
  drops ingredients in diet-excluded categories (`Categories.diet_category_ids/1`)
  — so "chicken" and "salmon" are excluded from a vegan plan, which the substring
  layer can't do. Vegan/vegetarian use the **positive** `#vegan`/`#vegetarian`
  tag (`Food.recipe_ids_with_diet_tag/2`, precomputed by `DietClassifier`);
  **pescatarian** has no such tag (it's "vegetarian ∪ fish-only"), so it uses the
  **inverse** `Food.pescatarian_recipe_ids/1` — keep recipes with no meat/poultry
  ingredient, fish allowed, computed over the candidate set, conservative on
  uncategorized ingredients. The effective diet is `effective_diet_mode/2`: a
  vegan/vegetarian/pescatarian blueprint, else the user's profile `diet_mode`
  (`Accounts.diet_mode/1`, which resolves only vegan/vegetarian — pescatarian is
  reachable only via a blueprint today).

On acceptance the entries are normalized (`normalize_entry/2`): calendar dates →
relative `day_index`, slot label → canonical `meal_type`, and the ingredient's
`unit_selection` resolved to real `measurement_unit_id` / `ingredient_portion_id`
FKs (falling back to grams if the model picked an invalid unit).

### What the avoid-foods filter matches against — and its blind spots

`reject_avoided/3` is a **case-insensitive substring** test (`String.contains?`)
run against two strings: a recipe's user-authored **title** and an ingredient's
**`name`** — which for USDA-imported ingredients is the **raw USDA description**
(`"Onions, raw"`, `"Beef, ground, 80% lean"`, `"Wheat flour, whole-grain"`;
`FoodParser` sets `name: attrs["description"]`). It *is* a real filter — a
dropped id never enters the provenance set, so the model can't submit it even by
guessing — but its reliability is bounded by that substring test:

| Avoid-term shape | As an ingredient/title filter | Why |
|---|---|---|
| Singular English food noun (`onion`, `beef`, `wheat`) | ✅ reliable | USDA descriptions lead with the noun, so the term is a substring (`onion` ⊂ `Onions, raw`) |
| Category / collective word (`legumes`, `grains`, `processed foods`, `cured meats`, `refined sugar`) | ❌ **no-op** | No single ingredient is literally named this → matches nothing; survives only as prompt text |
| Non-English surface (a Greek recipe title / localized ingredient name) | ❌ misses | The agent matches the **base English** name/title; `IngredientSearch.search_in_language/3` is **not** used in the loop |
| USDA synonym spelled differently (`maize` vs `corn`) | ⚠️ partial | Only the exact substring is caught — no alias expansion |
| Coincidental substring (`rice` ⊂ `licorice`, `corn` ⊂ `popcorn`) | ⚠️ false positive | Over-exclusion (safe direction) but noisy |

**What's missing / not built (the known gaps):**

1. **No synonym/alias expansion** — one term matches one spelling. "corn" won't
   catch "maize"; "shrimp" won't catch a title that only says "prawns".
2. **No cross-language matching** — English avoid terms vs. localized recipe
   titles or ingredient names simply don't match. The loop reads base English
   strings; the translated-search path exists but isn't wired into enforcement.
3. **No ingredient-composition awareness** — the substring sees only the food
   *name*, never a recipe's ingredient list, so **hidden** instances (gluten in
   soy sauce, dairy in a sauce, onion in a stock) are invisible. A compound
   **dish** is caught only when the term appears in its *title* ("Garlic Chicken").
4. **Collective terms need the category layer, which covers vegan/vegetarian
   (+WFPB) and pescatarian.** For every other diet, a collective avoid term is
   dead weight unless it's **hand-concretized** into specific nouns (why
   paleo/whole30 now list `rice/oats/beans/…` instead of just `grains/legumes`).
   There is no general "category → member foods" resolution for arbitrary avoid
   terms.

**Net:** the avoid-foods filter is dependable only for **concrete, singular,
English food nouns**. Collective/synonym/cross-language cases fall back to the
soft prompt line (`avoid_block/1`) and the model's judgement — not a guarantee.
The robust path for whole-category exclusion is the taxonomy filter
(`diet_mode` → `recipe_ids_with_diet_tag`/`pescatarian_recipe_ids`/
`diet_category_ids`), now covering vegan, vegetarian, WFPB, and pescatarian.

## Generation → persistence pipeline (`MealPlanGenerator`)

Generation and persistence are deliberately separate:

- **`generate_entries/5`** — delegates to `MealPlanAgent.run/5`; on agent error,
  falls back to a legacy single-shot, recipe-only pipeline (3 slots/day). Returns
  normalized entries.
- **`persist_entries_to_calendar/3`** — materializes entries onto calendar dates
  (`day_index` → `start_date + n`), creating `UserMeal`s. Recipe entries become
  `recipe_user_meals` (with `consume_portions: 1` so the calendar's
  `consume_portions / servings` scaling shows real numbers); ingredient entries
  become `ingredient_user_meals` with resolved unit FKs.
- **`run/5`** — the calendar convenience: `generate_entries` then
  `persist_entries_to_calendar`, returning `{:ok, created, skipped}`.

## Blueprints as briefs

A `MealBlueprints.Blueprint` (a reusable, possibly condition-linked template) is
flattened to a free-text brief via `blueprint_preferences/1` — name, description,
condition, a **macro-balance target** (distilled from the per-meal
protein/carbs/fats split, omitted for a neutral 30/40/30 split), and
preferred/avoid nutrients + compounds + foods — and fed to the agent as
`preferences`. The agent reads free text, not the structured tree. The blueprint's
`avoid_foods` additionally drives the hard avoid-foods enforcement above.

> **Macro split is a *soft* target.** It reaches the planner only as this brief
> line; nothing re-checks the generated plan's actual macro ratios against it at
> generation time (the eval's `calorie_fit` checks energy, not the P/C/F split).
> So a keto brief *asks* for ~75% fat but isn't *guaranteed* it.

## Dependencies

- **Recipe search** (`Mehungry.Search.RecipeVectorSearch`): pgvector cosine
  similarity over OpenAI `text-embedding-3-small` recipe embeddings, with a
  **full-text fallback** when embeddings are unavailable. This is what makes
  `search_catalog` return relevant recipes for a natural-language query.
- **Nutrition** (`Food.NutrientCalculation` → `recipes.nutrients`, denormalized
  `ingredient_user_meals.nutrients`, `NutrientUtils.summarize_meals_nutrients/1` →
  `macro_summary/1`): the calendar's per-day macro totals a plan produces.
- **History** (`Mehungry.History`): recent meals in, materialized meals out.

## Feature code map

| Module | Role |
|---|---|
| `apps/mehungry/lib/mehungry/ai/agents/meal_plan_agent.ex` | The tool-use loop, validation, normalization |
| `apps/mehungry/lib/mehungry/ai/meal_plan_generator.ex` | generate / persist / legacy fallback |
| `apps/mehungry/lib/mehungry/meal_blueprints.ex` | `blueprint_preferences/1`, `store_plan_meals/2` |
| `apps/mehungry_web/.../calendar_live/index.ex` | Calendar trigger + personal avoid-list flagging |
| `apps/mehungry_web/.../meal_blueprint_live/index.ex` | Blueprint-plan trigger |
| `apps/mehungry_web/lib/mehungry_web/api/meal_plan_worker.ex` | Mobile REST async generation |

---

# Part 2 — Evaluation

How we test whether the planner produces **good** plans, not just structurally
valid ones. The product question: *given a user's brief, does the generated 7-day
plan actually meet it* — hit the slots, vary the recipes, respect avoid-foods, and
land near the calorie target?

## Why this exists

The pre-existing tests (`apps/mehungry/test/mehungry/ai/agents/plan_provenance_test.exs`)
only exercise the **deterministic plumbing** — provenance, slot/date validity,
avoid-foods *filtering*, quantities. Every one of them bypasses the LLM. Nothing
measured whether the resulting plan was *good*. This harness closes that gap.

## Design — three layers, cheapest first

| Layer | What | Status |
|---|---|---|
| **1 — Deterministic scorer** | Objective, LLM-free checks over the agent's output | **Built** |
| 2 — LLM-as-judge | Soft/culinary qualities (coherence, "does breakfast read as breakfast", variety *feel*) | Not built yet |
| 3 — Scenario matrix | A golden set of briefs × N runs → aggregate pass rates | Partially (two scenarios) |

Layer 1 is the backbone: reproducible, free, regression-safe. Layers 2–3 build on it.

### Test at the cheapest level that answers the question

Whether a given **diet pattern** (`MealBlueprints.DietPatterns`, 21 of them) is
honored is decided by *deterministic* mechanisms — the avoid-foods filter
(`MealPlanAgent.reject_avoided/3`) and the brief (`blueprint_preferences/1`) — not
by the LLM. So we **do not** run the agent 21× to re-check a filter:

- **Mechanism tests** (`diet_patterns_mechanism_test.exs`) — all 21 diets, **$0**,
  in CI: assert that each diet's avoid filter removes every avoid term from the
  catalog, that the brief carries the diet's avoid foods, and that a plan is still
  constructible. The per-diet survivor report surfaces catalog coverage.
- **Agent eval** — the LLM runs **once per full-feature evaluation** on a
  representative diet (the Low-FODMAP scenario below), to prove the agent actually
  *uses* the filtered candidates and submits a valid plan.

This separates the two **enforcement layers**: avoid-foods is literal substring
matching — the *specific-food* layer (onion, garlic, honey). It deliberately does
not catch category terms (Vegan's `"meat"` ≠ `"chicken"`). That's the job of the
*category* layer — `Food.recipe_ids_with_diet_tag/2` + `Categories.diet_category_ids/1`,
the same deterministic taxonomy `DietClassifier` and the profile `diet_mode` use —
which the agent's `search_catalog`/`search_ingredients` now apply (see
`meal_plan_diet_filter_test.exs`). Category filtering, **not embeddings**:
embeddings are right for ranking but too fuzzy/unauditable for a hard exclusion.
The mechanism test pins the division of labour so neither layer is expected to do
the other's job.

## Where the eval code lives

| File | Role |
|---|---|
| `apps/mehungry/test/support/eval/meal_plan_scorer.ex` | **`MealPlanScorer`** — pure scorecard over normalized plan entries |
| `apps/mehungry/test/support/eval/meal_plan_catalog.ex` | **`MealPlanCatalog`** — seeds a representative fixture catalog + blueprints (with nutrition + embeddings) |
| `apps/mehungry/test/support/eval/embedding_client_stub.ex` | **`EmbeddingClientStub`** — deterministic offline embedding (test `:embedding_client` seam) |
| `apps/mehungry/test/support/eval/token_meter.ex` | **`TokenMeter`** — tallies Anthropic token usage per run via telemetry |
| `apps/mehungry/test/mehungry/ai/eval/meal_plan_scorer_test.exs` | Deterministic unit tests pinning the scorer's own behavior |
| `apps/mehungry/test/mehungry/ai/eval/diet_patterns_mechanism_test.exs` | Deterministic, **token-free** coverage of all 21 diet patterns' filter + brief |
| `apps/mehungry/test/mehungry/ai/agents/meal_plan_diet_filter_test.exs` | Deterministic coverage of the agent's category diet filter (vegan excludes beef) |
| `apps/mehungry/test/mehungry/ai/eval/meal_plan_quality_eval_test.exs` | **Live eval** — runs the real agent, scores it (`@moduletag :ai_eval`) |

All live under `test/` (compiled only in `:test`), so none of this ships in the release.

## The scorer (`MealPlanScorer.score/2`)

Takes the normalized entries `MealPlanAgent.run/5` returns
(`MealPlanAgent.normalize_entry/2`) plus a `context` map, and returns a scorecard:

```elixir
%{
  checks: [%{key:, status: :pass | :warn | :fail | :skip, score: 0.0..1.0, detail:}],
  score:  0.0..1.0,   # mean of non-skipped check scores
  passed?: boolean,   # score >= 0.8 AND no :fail check
  summary: "..."
}
```

### Checks

| Check | Rule | On violation |
|---|---|---|
| `completeness` | 35 entries submitted (7 days × 5 slots) | `:fail` if none, `:warn` if partial |
| `all_slots_filled` | every (day, meal_type) filled exactly once | `:warn` + missing/dupe counts |
| `variety` | no recipe used more than **2×**/week (the agent's own rule) | `:warn`, score drops per excess placement |
| `snacks_are_ingredients` | snack slots are a whole-food ingredient, not a recipe | `:warn` |
| `avoid_foods` | **hard rule** — no entry's resolved food name contains an avoid term | `:fail` (fails the whole card) |
| `preferred_foods` | every preferred food appears somewhere | `:warn` |
| `calorie_fit` | each day's energy within **±20%** of the target | `:warn`; `:skip` only if no target/data |

`avoid_foods` is end-to-end (resolves recipe/ingredient *names*), so it catches
leaks the filter-level unit test can't — e.g. a compound dish name like "Slow
Roasted **Garlic** Chicken".

### Context keys (all optional)

- `:avoid_terms` / `:preferred_terms` — downcased substrings
- `:recipe_names` / `:ingredient_names` — `%{id => name}` for name checks
- `:daily_calorie_target` — number; enables calorie-fit
- `:day_macros` — `%{day_index => %{energy_kcal: n, …}}`, produced by the caller
  via the app's own `NutrientUtils.summarize_meals_nutrients/1` → `macro_summary/1`

> **Parity, not reimplementation.** The scorer never computes macros itself — the
> caller hands it `:day_macros` built from the same function the calendar uses, so
> the eval can't drift from the product. (See the REST↔LiveView parity principle
> in `CLAUDE.md`.)

## The fixture catalog (`MealPlanCatalog.seed/1`)

Seeds one owner user, 16 slot/cuisine-tagged recipes (incl. a deliberate "Garlic"
dish as avoid-foods bait), 10 whole-food snack ingredients, and two blueprints:

- `blueprint_plain` — "Balanced Week", no avoid list
- `blueprint_low_fodmap` — "Low-FODMAP (IBS)", `avoid_foods: ["onion", "garlic"]`

Returns a `context` ready for both the agent and the scorer (`recipe_names`,
`ingredient_names`, `user_id`, `start_date`, `daily_calorie_target`, both blueprints).

### Realism notes (important)

1. **Nutrition is wired.** Each recipe carries one nutrient-dense base ingredient
   at 100 g with slot-appropriate per-100g macros (`servings: 1`, so a meal
   contributes the full recipe), and each snack ingredient carries its own per-100g
   macros — populating `recipe.nutrients` (computed synchronously, since
   `create_recipe` only *enqueues* the real worker) and the denormalized
   `ingredient_user_meals.nutrients`. The eval then aggregates per-day macros
   through the app's own calendar path (`persist_entries_to_calendar` →
   `list_calendar_user_meals` → `format_user_meals` → `summarize_meals_nutrients`
   → `macro_summary`), so `calorie_fit` scores against real numbers. Note the fat
   node only materializes when a fat **subcategory** exists, so each profile
   includes a `Saturated Fat` slice; the macro names must match what the hierarchy
   builder + `macro_bucket` key on (`Total Fat`, not `Total lipid (fat)`).
2. **Vector search via a stubbed embedding client.** Production meal-planning
   uses pgvector search over OpenAI embeddings; the test env has no OpenAI key.
   Rather than let `search_catalog` silently degrade to strict full-text search
   (`plainto_tsquery` ANDs every term, and `vegetarian`→`no-meat` normalization
   drops matches — so the agent's descriptive queries returned ~0 recipes and it
   built all-ingredient plans), the harness runs the **real vector path**
   deterministically: a config seam (`:embedding_client`, set to
   `Mehungry.AI.EmbeddingClientStub` in `config/test.exs`) supplies an offline
   bag-of-words hashing embedding, and `MealPlanCatalog.seed/1` seeds each
   recipe's `embedding` column from the same function. Cosine similarity then
   ranks recipes by lexical overlap with the query (a "hearty mediterranean
   dinner" search returns the Mediterranean dinner first). If a future run shows
   empty recipe coverage, suspect this seam first.

## How to run

The live eval is tagged `@moduletag :ai_eval` and **excluded by default** (it calls
the Anthropic API — costs tokens, needs `ANTHROPIC_API_KEY`). The exclusion is set
in `apps/mehungry/test/test_helper.exs`.

```bash
# Deterministic scorer tests — free, run in normal CI:
mix test apps/mehungry/test/mehungry/ai/eval/meal_plan_scorer_test.exs

# Live quality eval — needs ANTHROPIC_API_KEY, spends tokens:
mix test --only ai_eval

# Multiple runs per scenario → pass rate (the LLM is nondeterministic):
EVAL_RUNS=5 mix test --only ai_eval
```

Each live run logs a formatted scorecard plus **catalog coverage** (distinct
recipes/ingredients used out of what was seeded).

> **Coverage is the key diagnostic.** A bad plan has two very different causes that
> look identical to a human tester: (a) the agent chose poorly → fix the prompt/
> model, or (b) the catalog was too thin → grow the catalog. The coverage line
> separates them. Always read it alongside the score.

## Token cost

`MealPlanAgent` runs the tool loop on **Haiku 4.5** (`claude-haiku-4-5-20251001`),
priced at **$1.00 / MTok input, $5.00 / MTok output**. The live eval tallies its own
usage via `TokenMeter` (a telemetry listener on `[:mehungry, :ai, :client, :request,
:stop]`) and logs a per-scenario report on test exit.

**Measured run (2026-10-23, `EVAL_RUNS=1`, fixture catalog, vector search working):**

| Scenario | API calls | Input tok | Output tok | Cost |
|---|---|---|---|---|
| balanced-week | 5 | 25,058 | 2,735 | ~$0.039 |
| low-FODMAP | 5 | 28,817 | 2,820 | ~$0.043 |

So a single 7-day plan costs **~$0.04**, and the full two-scenario run is **~$0.08**.
Multiply by `EVAL_RUNS`. Notes:

- Input dominates because it's an agentic loop — each `submit_plan` retry resends the
  whole growing conversation. Fewer retries (a better-steered agent) directly lowers cost;
  the `completeness`/iteration signals track this. (An earlier run where recipe search
  returned nothing cost ~2× as much — the agent made 9–10 calls flailing on empty searches.
  Making the catalog searchable both fixed quality *and* halved cost.)
- These are raw `input_tokens`/`output_tokens` from the Anthropic `usage` block; prompt-cache
  reads aren't separately surfaced, so real cost may be lower if the prefix caches.
- **No OpenAI/embedding cost** on this run — `search_catalog`'s embedding client is stubbed
  offline in test (see the catalog caveats). A real-data run that embeds against OpenAI would
  add embedding spend. Nutrition adds **no** API cost — it's all DB-side aggregation.

## Current scenarios & thresholds

| Scenario | Asserts |
|---|---|
| balanced week | completeness never `:fail`; avoid-foods never `:fail`; **≥60%** of runs pass overall |
| low-FODMAP | avoid-foods **never** `:fail` on any run (a single onion/garlic leak = failure) |

Thresholds are intentionally lenient for a thin fixture catalog; tighten them when
running against richer data.

## Measured so far (`EVAL_RUNS=1`, n=1 per scenario)

Every executed check passed. Structural + rule adherence (completeness, all-slots,
variety, snacks-are-ingredients) was 100%, the Low-FODMAP avoid-list held with zero
leaks, and **`calorie_fit` was 7/7 days within ±20% of 2000 kcal on both scenarios**
(day averages ~1940–1970 kcal). This is an existence proof, not a rate — run
`EVAL_RUNS=20` for a defensible pass-rate/accuracy figure. Nutritional accuracy and
rule adherence are measured; **culinary/semantic quality is not** (that's the Layer-2
judge, not yet built).

## Extending it

- **New scenario:** add a blueprint to `MealPlanCatalog` and a test clause that
  calls `run_scenario/5` + asserts. Reuse `MealBlueprints.blueprint_preferences/1`
  so the brief is built exactly as production builds it.
- **Calorie-fit is on** (`run_scenario/5` computes `:day_macros` per run from the
  calendar aggregation and the catalog supplies `:daily_calorie_target`). To make
  it stricter or more realistic, vary targets per scenario (e.g. a cutting vs
  maintenance brief) or point the harness at a nutrition-rich prod snapshot.
- **Layer 2 (LLM judge):** add a rubric'd judge behind a config seam (mirror the
  `:compound_plausibility_judge` pattern) so it stays mockable and off by default.

## Related

- [`ai_agents.md`](ai_agents.md) — `MealPlanAgent` internals in the broader agent context
- `CLAUDE.md` → Oban queues, subscription quotas, REST↔LiveView parity
