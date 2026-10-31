# AI Bot Personas, Setups & Recipe Orders

The AI-bot recipe pipeline can author recipes in the voice of a **character**
(village grandma, auntie, tavern, restaurant, dietologist…) rooted in a
**place**, built around **seed ingredients with roles**, optionally shaped by a
health **condition**, and carrying an optional **story** — so the output stops
reading as generic AI copy.

## The three concepts

| Concept | Schema | What it is |
|---|---|---|
| **Persona** | `AI.Bot.Persona` (`ai_bot_personas`) | A reusable authoring voice. `voice_prompt` is the second-person identity injected into generation and polish; `uses_hashtags` gates hashtags. Seeded + admin-CRUD at `/professional/ai-bot/personas`. |
| **Recipe Setup** | `AI.Bot.RecipeSetup` (`ai_bot_recipe_setups`) | A named bundle: `cuisine` (**the top generation constraint**) + `persona` + `origin` (free text, e.g. "Rethymno → Crete → Greece") + `story` + optional `condition` + `diet_direction` + seed ingredients. Decoupled from the calendar. Admin-CRUD at `/professional/ai-bot/setups`. |
| **Seed ingredient** | `AI.Bot.RecipeSetupIngredient` (`ai_bot_recipe_setup_ingredients`) | An ingredient on a setup with a `role`: `primary` (build around) / `garnish` / `spice` / `avoid` (hard exclude). Auto-populatable from the setup's condition via `Bot.populate_setup_ingredients_from_condition/1` (encouraged → primary, discouraged → avoid). |

A persona (e.g. "Grandma") can back many setups ("Grandma from Crete", "Grandma
from Naxos").

> **Ready-to-fill examples:** [`ai_bot_prompt_routes.md`](ai_bot_prompt_routes.md)
> has the full Persona/Setup/Order **field reference** plus **10 fully-specified
> routes** (Cretan grandma, Neapolitan nonna, Osaka home cook, Oaxacan abuela,
> Istanbul meyhane, Provençal bistro, Mumbai tiffin, Athens dietologist, Lisbon
> seaside, Bangkok street) to copy into the admin UI.

## Cuisine-first generation

**Cuisine is the single most important constraint** and everything descends from
it. A setup carries an explicit `cuisine`; when it's blank,
`Bot.setup_cuisine/1` derives one from the last place segment of `origin`
("Rethymno → Crete → Greece" → "Greek", via a small country→demonym map, unknown
places returned verbatim). The resolved cuisine:

- leads the generation **system prompt** (`cuisine_block/1` in `RecipeAgent`) and
  the user-facing description (`"Cuisine: <x>. …"`);
- forces the model to **first commit to one real, named, traditional dish** of the
  cuisine before listing ingredients (the anti-invention anchor — see the
  [design note](#why-not-themealdb) on why we do this instead of hitting an
  external recipe DB);
- is stamped onto the persisted recipe's `cousine` column so the **cover-image**
  prompt styles the photo per cuisine (`ImageGenerator.cuisine_setting/1`) instead
  of the old hardcoded warm/rustic "amber" look every image shared.

The prompt was also de-slopped: the "think about the full flavour profile…"
padding directive and the purple-prose description instruction were removed,
because both actively pushed the model toward the invented, over-complicated
output cuisine-first is meant to suppress.

### Known limitations (cuisine)

Deliberately scoped out — documented so they're a conscious choice, not a
surprise:

- **Theme-only configs get no cuisine.** Cuisine flows only through a bound
  `RecipeSetup` (`Bot.build_brief/1` / `Bot.setup_cuisine/1`). A plain
  monthly-theme `AiBotConfig` with no setup ("cozy winter", no persona/setup) still
  generates cuisine-less — the prompt falls back to the theme description alone. The
  clean fix, if every config should be cuisine-anchored, is a `cuisine` field on
  `AiBotConfig` mirroring the setup one. Not built yet.
- **`derive_cuisine/1` is intentionally shallow.** It maps only ~15 countries to a
  demonym and returns anything else verbatim (so "Oaxaca" stays "Oaxaca"). It's a
  convenience default for a blank `cuisine` field — the reliable answer is an admin
  setting `cuisine` explicitly. Resist growing the map into a full gazetteer; if
  derivation ever needs to be better, a one-shot LLM call at setup-save time beats a
  hardcoded table.

## How a setup reaches generation

`Bot.get_context_for_date/2` resolves the **effective setup** with a
day → week → config cascade (each of `AiBotConfig`, `WeekConfig`, `DayConfig`
carries an optional `recipe_setup_id`). `Bot.build_brief/1` turns the setup into
the keyword brief passed to `RecipeAgent.run/2` (now including `cuisine`):

- `system_prompt/1` — with a persona, the opening identity becomes the
  character's voice (`persona_block/1`), and seed ingredients steer selection
  (`ingredient_directive/1`, which also hard-bans the `avoid` list).
- `polish_prose/2` — with a persona, the final rewrite speaks in the
  character's voice instead of the generic Instagram/Pinterest "food writer"
  voice (`polish_system_prompt/2`). Hashtags are emitted only when
  `persona.uses_hashtags` is true.

With **no** setup/persona the behavior is unchanged (generic expert-chef voice,
social polish, hashtags).

The `avoid` role feeds the same post-generation hard-exclude guard used for
condition-discouraged ingredients — both workers share it via
`AI.Bot.RecipeGeneration.generate/4` (the guard, meal-prompt hints, condition
guidance resolution, and encouraged/discouraged prompt injection all live there,
so the daily and order paths can't drift).

When a setup carries a **condition**, both workers now resolve its
encouraged/discouraged ingredients **live** at generation time
(`RecipeGeneration.condition_guidance/1` → `Health.ingredient_guidance_for_condition/1`)
— the encouraged names are injected into the description and the discouraged ids
join the avoid-guard. This no longer depends on the setup having been "populated
from condition" into seed ingredients.

A condition can imply a large ingredient set, so the two lists are bounded before
they reach the prompt: **discouraged** is a soft hint capped at 50 (the *full* set
is still enforced by the id-guard regardless), while **encouraged** is a small
**random sample of 12** (`RecipeGeneration.encouraged_names/1`) — sampled rather
than taking the alphabetical head, so "build around these" stays focused per
recipe and varies across a batch.

> **Log-line change:** the avoid-guard's retry/exhaustion warnings are now emitted
> by the shared module, so they carry the `[RecipeGeneration] <label>` prefix
> (label = the meal type, e.g. `[RecipeGeneration] breakfast: …`) instead of the
> old per-worker `[DailyRecipeGenerationWorker]` / `[RecipeOrderWorker]` tags. The
> meal-type label still identifies the source; grep on `RecipeGeneration` for guard
> activity across both workers.

## Recipe Orders (ad-hoc batches)

`AI.Bot.RecipeOrder` (`ai_bot_recipe_orders`) requests **N recipes for a setup**,
outside the monthly calendar. Placed at `/professional/ai-bot/orders`, fulfilled
by `Mehungry.ObanWorkers.RecipeOrderWorker` (queue `:ai_agents`):

- Generates `quantity` recipes from the setup's brief (cycling meal types when
  `meal_type` is nil), applying the `avoid` guard.
- Order recipes are `AiBotRecipe` rows with `recipe_order_id` set,
  `bot_config_id: nil`, `scheduled_date: today`, `status: "pending_review"` —
  so they slot into the existing review queue grouped by date. NULL
  `bot_config_id` rows are distinct under the existing unique index, so ordering
  many recipes never collides.
- No publish scheduling — order recipes are approved/published manually from the
  review queue.

## Why not TheMealDB

We considered grounding generation in an external open recipe DB
([TheMealDB](https://www.themealdb.com/)) and **deliberately chose not to**:

- The value of retrieval grounding is highest when the model *lacks* the
  knowledge. The world's documented cuisines and their canonical dishes are
  saturated in the training data — injecting a real dish's ingredient list tells a
  capable model almost nothing new.
- Coverage is tiny (~300 dishes, ~30 areas) and whiffs hardest on the
  **condition-based** recipes, which are exactly where coherence matters most.
- It's licensed external content and we **republish to social**, so it's legal
  friction for marginal upside, plus a new failure surface in the 2am cron job.

Instead we capture the *intent* — anchoring on a real dish — with the
**"commit to one real, named, traditional dish first"** prompt step, which uses
the model's own internal knowledge and covers every cuisine for free. If we ever
catch the model inventing *fake* dish names, the corrective is a small **curated
list we own** (a hand-written seed, not an API), not a live dependency.

## Files

- Schemas: `apps/mehungry/lib/mehungry/ai/bot/{persona,recipe_setup,recipe_setup_ingredient,recipe_order}.ex`
  (`recipe_setup` carries the `cuisine` field; migration
  `20260824000000_add_cuisine_to_recipe_setups`)
- Cuisine resolution: `Mehungry.AI.Bot.setup_cuisine/1` + `derive_cuisine/1`
- Cuisine-aware cover images: `Mehungry.AI.ImageGenerator.generate/3` (reads the
  recipe's `cousine` column)
- Context: `Mehungry.AI.Bot` — persona/setup/order CRUD, `build_brief/1`, `populate_setup_ingredients_from_condition/1`, `get_context_for_date/2`
- Generation: `Mehungry.AI.Agents.RecipeAgent` (`run/2`, `system_prompt/1`, `polish_prose/2`)
- Shared generation helpers: `Mehungry.AI.Bot.RecipeGeneration` (meal prompts, live condition guidance, avoid-guard) — used by both workers
- Workers: `DailyRecipeGenerationWorker`, `RecipeOrderWorker`
- Admin UI: `MehungryWeb.AiBotLive.{Personas,Setups,Orders}` + the setup picker / per-week / per-day override in `AiBotLive.Config`
- Seeds: predefined personas in `apps/mehungry/priv/repo/seeds.exs`
