# Diet-Pattern Accuracy Evaluation

An honest audit of the 21 ready-made diet patterns in
`Mehungry.MealBlueprints.DietPatterns` — **how faithfully each one, as the app
actually enforces it, reproduces what its audience means by that diet**, what is
missing, and *why* it's missing (data we don't have vs. mechanism we haven't
built vs. a deliberate product line).

> Read this next to `docs/ai/meal_plan.md` (how generation + enforcement work)
> and `docs/meal_blueprints.md` (the blueprint product). Source of the patterns:
> `apps/mehungry/lib/mehungry/meal_blueprints/diet_patterns.ex`.

---

## 1. First, be clear about what a diet pattern *can* express

A `DietPatterns` descriptor only has these levers, and they are **not equally
strong**. Accuracy is capped by the weakest lever a given diet depends on.

| Lever | Field | How it's enforced at generation | Strength |
|---|---|---|---|
| **Exclude specific foods** | `avoid_foods` | Literal **substring** filter removes catalog candidates before the model sees them, and an end-to-end name re-check on the final plan (`MealPlanAgent.reject_avoided/3`, scorer `avoid_foods`) | **Hard** (but literal) |
| **Exclude a whole food category** | derived `diet_mode` | Taxonomy filter (`#vegan`/`#vegetarian` tags + `Categories.diet_category_ids/1`) — **only `:vegan` / `:vegetarian`** are inferred (`diet_mode_from_blueprint/1`) | **Hard**, but only two diets |
| **Prefer foods** | `preferred_foods` | Named in the free-text brief; model's discretion | **Soft** |
| **Prefer / limit nutrients** | `required_nutrients` / `avoid_nutrients` | Named in the brief; **not** verified against `recipe.nutrients` at plan time | **Soft** |
| **Prefer / limit compounds** | `required_compounds` / `avoid_compounds` | Named in the brief | **Soft** |
| **Macro ratio** | per-meal `protein_pct/carbs_pct/fats_pct` | Now summarised into one brief line (`blueprint_preferences/1 → macro_line/1`); **soft**, nothing re-checks the plan's real ratio | **Soft** (was: *not passed at all*) |
| **Calorie level** | — | Diet patterns set **no** calorie target by design (`days/1`); the user's profile target drives `calorie_fit` in eval only | **Absent** |

**Everything below follows from this table.** A diet whose essence is "exclude
named foods" (Low-FODMAP, Gluten-Free, Vegan) we can render *well*. A diet whose
essence is a **quantitative threshold, a macro ratio, a portion size, a glycemic
value, or a phase schedule** we can only *gesture at* through the soft brief.

> **The `avoid_foods` lever is substring-only, and matched against raw USDA
> ingredient descriptions** (`"Onions, raw"`) + user-authored recipe titles. It's
> reliable for concrete singular English nouns, a **no-op** for collective words
> (`grains`, `legumes`), and **blind across languages** and to hidden ingredients.
> The full matrix of what it does/doesn't catch — and why — is documented in
> [`../ai/meal_plan.md` → *What the avoid-foods filter matches against*](../implementation/ai/meal_plan.md#what-the-avoid-foods-filter-matches-against--and-its-blind-spots).
> This is *why* §4 concretizes category words into specific nouns.

### The structural gaps that hit many diets at once

1. **Macro ratio is a soft request, never a guarantee.** It now reaches the
   planner (previously it was silently dropped — see §4), but nothing re-checks
   the generated plan's actual P/C/F against it. A keto brief *asks* for ~75%
   fat; the plan may land at 50%.
2. **No quantities / thresholds.** We can't express "<50 g net carbs/day"
   (keto), "<1500 mg sodium" (DASH/low-sodium as a number), "<2 g/serving sugar",
   or FODMAP *portion* thresholds (½ avocado is low-FODMAP, a whole one isn't).
   We only have presence/absence of named foods + a ratio.
3. **No glycemic-index / glycemic-load data.** `low_glycemic`, `zone`, and the
   "low-GI" half of `low_carb` can't actually rank foods by GI — we have USDA
   macros, not GI. We approximate with "avoid white bread/rice/sugar".
4. **No phases or time dimension.** Atkins (induction → OWL → maintenance),
   Whole30 (a 30-day elimination *then reintroduction*), and any
   time-restricted/fasting pattern collapse to a single steady-state week. The
   blueprint is 7 identical days by construction (`days/1`).
5. **No nutritional-adequacy / supplementation layer.** Vegan B12, iron, omega-3;
   low-fat fat-soluble vitamins; keto electrolytes/fiber. We never warn or
   compensate. Out of scope today, but it's the difference between "a themed menu"
   and "a safe diet".
6. **Category exclusion covers vegan/vegetarian/WFPB and pescatarian.**
   `diet_mode` is inferred (`diet_mode_from_blueprint/1`): a **subset** check —
   any avoid-set containing `{meat,poultry,fish}` + `dairy` + `eggs` resolves to
   `:vegan`, so **Whole-Food Plant-Based also gets the full category filter**
   (its extra `oil`/`refined sugar` terms don't break the match); `meat`+`poultry`
   without `fish` resolves to `:pescatarian` (see §4). Vegan/vegetarian filter
   recipes by the **positive** `#vegan`/`#vegetarian` tag; pescatarian — which
   has no such tag — filters by the **inverse** `Food.pescatarian_recipe_ids/1`
   (drop recipes containing meat/poultry, keep fish). The remaining exclusion
   diets (paleo, Whole30, gluten-free, dairy-free) still rely entirely on the
   **literal substring** `avoid_foods` list — coverage only as good as that
   hand-written list is exhaustive.

---

## 2. Per-diet scorecard

Rating = how close the *enforced* pattern is to what the audience means.
🟢 strong · 🟡 partial · 🔴 weak.

### Exclusion-defined diets (our strong suit)

| Diet | Rating | What we capture | What's missing & why |
|---|---|---|---|
| **Low-FODMAP** | 🟢 | The defining lever *is* an avoid-list (onion, garlic, wheat, legumes, high-FODMAP fruit) — hard-enforced. Good preferred list. | **Portion thresholds** — FODMAP is dose-dependent (¼ avocado OK, whole not; a little hard cheese OK). We can't express "allowed in small amounts". **Elimination→reintroduction phases** collapsed to one steady week. Missing foods that could be named: `mango, asparagus, mushroom, cauliflower, sugar snap peas`. |
| **Vegan** | 🟢 | Both layers fire: `avoid_foods` substring **and** the `:vegan` category filter (drops chicken/salmon/cheese the substring list can't). Best-enforced diet we have. | **B12 / iron / omega-3 / vitamin D adequacy** — never addressed. **Honey→** caught; gelatin/whey/casein rely on category tagging being correct. |
| **Vegetarian** | 🟢 | Same two-layer enforcement as vegan, keeping eggs + dairy. | Adequacy (iron, B12) not addressed. |
| **Gluten-Free** | 🟢 | Avoid-list now covers wheat, barley, rye, **spelt, farro, bulgur, semolina, seitan**, bread, pasta, couscous, beer (hardened — see §4). Medically the right shape for celiac. | **Cross-contamination / hidden gluten** (malt, soy sauce, "modified food starch") — substring can't see an ingredient list, only the food name. `malt` deliberately *not* added (would wrongly exclude gluten-free maltodextrin). No category backstop, so accuracy = list completeness. |
| **Dairy-Free** | 🟢 | milk, cheese, yogurt, butter, cream, ice cream. `"milk"` substring also catches buttermilk/milkshake. | Hidden dairy (whey, casein, ghee) not named; no category backstop. |
| **Pescatarian** | 🟢 | **Now gets a category filter** (§4): `diet_mode → :pescatarian` drops meat/poultry **recipes** (`pescatarian_recipe_ids/1`, the inverse of the vegan/vegetarian tag) **and** ingredients (`diet_category_ids(:pescatarian)`), keeping fish — catching beef/chicken the substring list couldn't. Avoid-list also hardened as a backstop. | Reachable only via a pescatarian **blueprint**, not a profile `diet_mode` (`Accounts.diet_mode/1` still returns only vegan/vegetarian). Conservative: a recipe with any uncategorized ingredient is dropped. |
| **Paleo** | 🟡→🟢 | **Hardened** (§4): grain/legume **category words now backed by specific foods** (rice, oats, quinoa, corn, cereal, beans, lentils, chickpeas, peanut, soy, tofu), so the substring gate actually bites. Good preferred list (meat, fish, eggs, veg, fruit, nuts). | Bare `"beans"` conservatively also excludes green beans (safe-direction over-exclusion). Any un-named grain/legume still leaks (no category layer for paleo). |
| **Whole30** | 🟡 | **Hardened** (§4): same grain/legume specifics as paleo, plus `honey`/`maple syrup` for Whole30's *total* added-sugar ban. | Whole30's essence is a **strict 30-day elimination + a structured reintroduction** — we model a permanent steady week, missing the entire temporal protocol. Green-bean over-exclusion as above (Whole30 technically allows pods). |
| **Whole-Food Plant-Based** | 🟢 | **Gets the full `:vegan` category filter** (the subset inference matches — its extra oil/sugar terms don't break it), so chicken/salmon/cheese are hard-excluded by taxonomy, not just substring. Plus `oil` excludes olive/coconut oil for the no-added-oil rule. | The "**minimally processed**" essence beyond oil is undetectable (we can't read processing level); vegan adequacy (B12/iron) unaddressed. |

### Macro-ratio-defined diets (soft by nature)

| Diet | Rating | What we capture | What's missing & why |
|---|---|---|---|
| **Ketogenic** | 🔴→🟡 | Macro split (75% fat / 5% carb / 20% protein) **now reaches the brief** (§4), and the avoid-list is **enriched** (§4) — now also corn, cereal, oatmeal, honey, fruit juice, chips on top of bread/pasta/rice/potato/sugar/banana/beans/oats. | Keto is **defined by a hard carb threshold (<20–50 g net carbs/day)**, which we can't express or verify — the brief only *asks* for 5% carbs and nothing checks the result. `"milk"` deliberately not added (would exclude keto-friendly coconut/almond milk). No "net carbs" concept. No electrolyte/fiber adequacy. |
| **Low-Carb** | 🟡 | Macro split (20% carb) now in brief; avoid-list **enriched** (§4) with fruit juice, honey, corn, cereal, candy, pastries on top of bread/pasta/rice/potato/sugar/sugary drinks. | No threshold; "low-carb" is a spectrum (50–150 g) we pin only as a ratio. GI not modelled. |
| **Atkins** | 🟡 | Macro split (10% carb / 60% fat) in brief; low-carb avoid-list. | **Phases** are Atkins' whole identity (induction 20 g → gradual reintroduction) — we model only a single very-low-carb week, effectively just "induction forever". |
| **High-Protein** | 🟡 | Macro split (40% protein) now in brief; strong preferred list (chicken, eggs, fish, Greek yogurt, cottage cheese, tofu). | Protein is a **soft** request — nothing enforces grams/kg bodyweight or verifies the plan actually hits 40%. No per-bodyweight target (we have no weight at blueprint level). |
| **Low-Fat** | 🟡 | Macro split (15% fat) in brief; avoids fried foods, butter, fatty meat, cream, full-fat cheese; limits total + saturated fat. | Soft ratio only; no gram cap. Fat-soluble-vitamin adequacy not addressed. |
| **Zone** | 🟡 | 40/30/30 split now in brief; avoids white bread/rice/sugar. | Zone's actual method is **"blocks" (portioned protein/carb/fat units) favouring low-GI carbs** — we have neither block portioning nor GI. We approximate with the ratio + a few avoid foods. |
| **Low-Glycemic** | 🟡 | Avoids sugar, white bread, white rice, sugary drinks, sweets, fruit juice; encourages fiber; good preferred list (legumes, whole grains, berries). | **No glycemic-index data** — the defining axis of the diet. We proxy GI with "avoid refined carbs", which is directionally right but can't rank e.g. watermelon vs. berries. |

### Pattern / "encourage"-defined diets (menu-shaped, we do OK)

| Diet | Rating | What we capture | What's missing & why |
|---|---|---|---|
| **Mediterranean** | 🟢 | This is fundamentally a *preferred-foods + ratio* pattern, which is exactly what we express well: olive oil, fish, legumes, whole grains, veg, nuts, Greek yogurt; encourage omega-3/fiber/MUFA, limit sat-fat/added-sugar/sodium; 20/45/35 split. | All soft (no verification), and "limit red meat / moderate dairy" is a *frequency* rule we can't encode (we have no per-week frequency lever). Still, the pattern's loose nature means soft enforcement is genuinely adequate here. |
| **DASH** | 🟢 | Preferred produce/whole-grains/low-fat-dairy; encourage fiber, **limit sodium** (named), limit sat-fat/added-sugar; 18/55/27. Avoids cured meats, canned soup, salty snacks. | DASH is officially a **numeric sodium target (1500–2300 mg) + specific daily servings counts** — we can't hit the number or the serving counts, only the direction. |
| **MIND** | 🟢 | Blends Med + DASH; leafy greens, berries, nuts, olive oil, fish; limit butter/fried/pastries/sweets/red meat. | MIND is literally defined as **10 "brain-healthy" food groups with weekly serving frequencies** (berries ≥2×/wk, greens ≥6×/wk) — no frequency lever, so we lose the quantitative core. |
| **Nordic** | 🟢 | Rye/oats, berries, root veg, fatty fish, rapeseed oil; encourage omega-3/fiber; 18/52/30. | Soft; regional-sourcing essence ("local, seasonal") is cultural and not encodable. |

---

## 3. Patterns of what's missing (the "why")

Grouping the gaps by **root cause** — this is the real answer to "why is it
missing":

1. **We have USDA macros + food names, not thresholds or GI.** → every
   quantitative diet (keto net-carbs, DASH/low-sodium milligrams, low-GI/Zone
   glycemic load, portion-dependent FODMAP) can only be *approximated*. Missing
   because the **data** isn't there, not the mechanism.
2. **The blueprint is steady-state (7 identical days).** → every **phased**
   diet (Atkins, Whole30, fasting/time-restricted) loses its defining schedule.
   Missing because the **schema** has no time/phase dimension by design.
3. **Category exclusion is wired for only vegan/vegetarian.** → every other
   exclusion diet leans on the literal `avoid_foods` list, so "category words"
   (`grains`, `legumes`, `meat` for pescatarian/WFPB) silently leak specific
   foods. Missing because the **mechanism** (`diet_mode_from_blueprint/1`) was
   scoped to two diets.
4. **Soft targets aren't verified.** → macro ratios and nutrient prefers reach
   the model as text but nothing re-checks the output. Missing because the
   **enforcement loop** stops at food exclusion; it doesn't close a feedback loop
   on macro/nutrient composition.
5. **No adequacy/safety layer.** → vegan B12, keto electrolytes, low-fat
   vitamins. Deliberately **out of product scope** (we don't publish medical
   advice — see the `Health` YMYL stance in `CLAUDE.md`).

---

## 4. What was fixed in this pass (low-hanging fruit)

Shipped in the same change as this doc — all low-risk, high-clarity:

1. **Macro split now reaches the planner.** `blueprint_preferences/1` was
   dropping the per-meal P/C/F ratio entirely — keto's 75% fat, high-protein's
   40% protein, etc. were computed, stored, and never communicated to the agent.
   Added `macro_line/1`: one brief line (`"Target macro balance: about X%
   protein, Y% carbs, Z% fat"`), omitted for a neutral 30/40/30 split so plain
   "balanced" blueprints aren't given a redundant cue. This is the single
   biggest accuracy win — it turns all 7 ratio-defined diets from 🔴 "ratio
   ignored" to 🟡 "ratio requested". Still soft (unverified).
2. **Pescatarian avoid-list hardened** — added beef, pork, lamb, chicken,
   turkey, bacon, sausage. Pescatarian gets no category filter, so its old
   `["meat","poultry"]` let every specific meat through.
3. **Gluten-free avoid-list hardened** — added spelt, farro, bulgur, semolina,
   seitan (all unambiguous gluten sources). `malt` intentionally omitted to
   avoid excluding gluten-free maltodextrin.
4. **Paleo & Whole30 grain/legume category words backed by specific foods** —
   rice, oats, oatmeal, quinoa, corn, cereal, beans, lentils, chickpeas, peanut,
   soy, tofu (both diets lack a category filter, so the category words alone were
   dead weight). Whole30 also gained honey + maple syrup for its total
   added-sugar ban.
5. **Keto & low-carb avoid-lists enriched** — keto: corn, cereal, oatmeal,
   honey, fruit juice, chips; low-carb: fruit juice, honey, corn, cereal, candy,
   pastries. (`milk` left off keto to avoid excluding coconut/almond milk.)
6. **Pescatarian category filter** — `diet_mode_from_blueprint/1` now infers
   `:pescatarian` (meat+poultry, no fish); the agent's recipe filter gained
   `Food.pescatarian_recipe_ids/1` (keep recipes with no meat/poultry ingredient,
   fish allowed — the inverse of the `#vegan`/`#vegetarian` positive tag, since
   pescatarian has no such tag) and the ingredient/prompt layers now accept
   `:pescatarian`. Gives pescatarian the same hard category backstop that
   vegan/vegetarian enjoy, instead of relying on the substring avoid-list alone.

Covered by the token-free regression tests
(`diet_patterns_mechanism_test.exs` + `meal_plan_diet_filter_test.exs`, all
passing).

## 5. Recommended next steps (not yet done — need a decision)

Ranked by value / effort:

1. ~~**Name specific grains/legumes in paleo, Whole30**~~ — **done** (§4). (WFPB
   didn't need it; it already gets the `:vegan` category filter.)
2. ~~**Extend `diet_mode_from_blueprint/1` to `:pescatarian`**~~ — **done** (§4).
   (Optionally extend `Accounts.diet_mode/1` so a *profile* pescatarian setting
   also triggers it on the browse/home feeds — deliberately left out to keep this
   change scoped to meal-plan generation.)
3. ~~**Enrich keto/low-carb avoid-lists**~~ — **done** (§4).
4. **Close the macro loop (verification).** The eval already aggregates per-day
   macros (`NutrientUtils.summarize_meals_nutrients`); add a soft `macro_fit`
   check (P/C/F within ±N% of the brief) alongside `calorie_fit`. Makes the
   ratio a *measured* target, not just a request. **Medium.**
5. **A `net_carbs`/threshold concept** for keto and a GI table for low-GI/Zone
   are the "real fidelity" items — both are **data-acquisition** projects, not
   quick wins. Document as known limitations until the data exists.
