# Nutrient Interactions ("Nutrition Insights")

The **"Nutrition Insights"** panel on the recipe detail page — e.g. *"Boosts iron
absorption"*, *"Reduces iron absorption"*, *"Needs fat to absorb"*. It inspects a
recipe's ingredients and surfaces known nutrient–nutrient interactions between them.

Code: `Mehungry.Food.NutrientInteractions`
(`apps/mehungry/lib/mehungry/food/nutrition/nutrient_interactions.ex`).
Panel component: `MehungryWeb.CoreComponents.nutrient_interaction_panel/1`.
Read surface: `RecipeDetailsComponent` (recipe modal / `/browse/:id`, `/home/:id`).

> **Status: HIDDEN (2026-10-22).** The panel is disabled on the recipe detail page.
> `RecipeDetailsComponent.maybe_load_recipe_async/3` forces `@interactions` to `[]`
> (so no DB query runs) and the render block is commented out (search "Nutrition
> Insights" in that file). The domain module and its tests are untouched and still
> pass — only the UI is hidden. See the accuracy assessment below for why.

---

## How it works

`NutrientInteractions.interactions_for_ingredients/1` takes a recipe's ingredient
IDs and runs a three-step pipeline:

1. **Load** — `IngredientNutrient` rows for those ingredients: `{ingredient_id,
   nutrient_name, amount}`, where `amount` is the USDA **per-100 g** value. Names
   are canonicalized via `NutrientNameNormalizer`.
2. **Classify "significant"** — an ingredient is treated as a meaningful source of
   a nutrient when its **per-100 g** amount clears a threshold (`@thresholds`,
   roughly 10% of the FDA Daily Value, e.g. Iron ≥ 1.8 mg, Calcium ≥ 130 mg,
   Vitamin C ≥ 9 mg per 100 g).
3. **Match rules** — a static list of ~10 hand-coded biochemistry rules
   (`@rules`), each naming two canonical nutrients and a relationship
   (`:enhances` / `:inhibits` / `:requires`) with a badge, label, detail, and a
   literature `source`. A rule fires when at least one ingredient significantly
   provides `nutrient_a` **and** (for enhances/inhibits) at least one provides
   `nutrient_b`. `:requires` rules (fat-soluble vitamins need dietary fat) fire
   either as a "needs fat" tip (no fat present) or a positive "fat enhances
   absorption" note (fat present).

The rules encoded today:

| Relationship | Rule | Badge |
|---|---|---|
| Vitamin C → Iron | Boosts iron absorption | positive |
| Calcium ⊣ Iron | Reduces iron absorption | warning |
| Zinc ⊣ Iron | May compete with iron | warning |
| Vitamin D → Calcium | Boosts calcium absorption | positive |
| Magnesium → Vitamin D | Supports vitamin D activation | positive |
| Vitamin C → Folate | Protects folate | positive |
| Fat ⟂ Vitamins A / D / E / K | Needs fat to absorb (or "fat enhances…") | tip / positive |

The relationships themselves are **real, established nutrition biochemistry** and
are cited per rule (NIH Office of Dietary Supplements, EFSA scientific opinions,
peer-reviewed papers). That part is sound.

---

## Accuracy assessment (why it's hidden)

**Perception: the science is correct, but the recipe-level *inference* is
low-signal and occasionally misleading.** The panel tells you that two interacting
nutrients are each "present somewhere in the ingredient list above a low per-100 g
threshold" — which is not the same as the interaction materially applying to *this
dish*. Concretely:

1. **It's presence-based, not dose-based — the core flaw.** Significance uses each
   ingredient's **per-100 g density**, never the amount actually used in the
   recipe. A pinch of a calcium-dense ingredient and a trace of an iron-dense one
   will fire *"Reduces iron absorption"* just as loudly as if the dish were built
   around both. This is the opposite of the nutrient-claim **badges**
   (`docs/food/nutrient_badges.md`), which scale every amount by the recipe's
   gram-weight. The interaction engine ignores quantity entirely.

2. **Co-presence ≠ meaningful interaction.** Real interaction magnitude depends on
   **doses and ratios** (e.g. calcium inhibits iron appreciably only past a certain
   calcium load and calcium:iron ratio), the **food matrix**, and **meal timing** —
   none of which are modeled. Firing on mere co-presence above ~10% DV/100 g
   produces a lot of technically-true-but-not-actionable flags.

3. **Heme vs non-heme iron is not distinguished.** The Vitamin C→Iron and
   Calcium⊣Iron effects are primarily about **non-heme (plant) iron**. Applied to a
   meat dish (heme iron, absorbed by a different pathway), the flags overstate or
   misstate the effect.

4. **Silent data-coverage dependency.** If an ingredient lacks `IngredientNutrient`
   rows, it simply doesn't contribute — a false negative with no signal to the
   user. (Unlike the badge pipeline, there is no coverage gate here.)

5. **"Warning" framing risk.** *"Reduces iron absorption — consider separating
   these at different meals"* on an everyday recipe reads as alarmist and isn't
   actionable at the recipe level. This is the most user-visible symptom and the
   likely reason it "doesn't look helpful."

**Net:** it ranges from trivially true (fat-soluble vitamin + any oil) to
misleading (iron warnings driven by trace per-100 g density). Good educational
*content*, unreliable *per-recipe conclusions*. Hiding it is the right call until
it becomes dose-aware.

---

## What would make it trustworthy (if revived)

- **Use real recipe amounts.** Compute per-serving nutrient amounts via the same
  gram-weight scaling the nutrition/badge pipeline already uses
  (`Food.NutrientCalculation`) instead of per-100 g density. This is the single
  biggest fix.
- **Gate on dose and ratio**, not co-presence — thresholds and ratios drawn from
  the cited literature (e.g. a calcium:iron ratio band for the inhibition flag).
- **Distinguish heme vs non-heme iron** before firing the iron rules.
- **Reuse the coverage gate** built for badges so thin-data recipes don't
  mis-fire or silently drop interactions.
- **Soften the voice** to educational tips, away from "warning / separate at
  different meals."

## Code pointers

- Rules + thresholds + matching: `Mehungry.Food.NutrientInteractions`.
- Recipe entry points: `Food.get_interactions_for_recipe/1` and
  `Food.get_interactions_for_ingredients/1` (`Food.Nutrients`). This panel is
  computed **live at read time** from `IngredientNutrient` rows — there is no
  stored interactions column, so hiding the UI fully removes the feature from
  users (no backfill needed to "turn it off").
- Note: the `/professional/maintenance` "Backfill Ingredient Interactions" button
  (`Food.enqueue_interaction_recalculation_for_all/0`) actually just delegates to
  the full nutrient recalculation worker; its label is stale and it is unrelated
  to this read-time panel.
- Tests (still green): `apps/mehungry/test/mehungry/food/nutrient_interactions_test.exs`.
