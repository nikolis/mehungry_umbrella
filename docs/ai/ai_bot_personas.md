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
| **Recipe Setup** | `AI.Bot.RecipeSetup` (`ai_bot_recipe_setups`) | A named bundle: `persona` + `origin` (free text, e.g. "Rethymno → Crete → Greece") + `story` + optional `condition` + `diet_direction` + seed ingredients. Decoupled from the calendar. Admin-CRUD at `/professional/ai-bot/setups`. |
| **Seed ingredient** | `AI.Bot.RecipeSetupIngredient` (`ai_bot_recipe_setup_ingredients`) | An ingredient on a setup with a `role`: `primary` (build around) / `garnish` / `spice` / `avoid` (hard exclude). Auto-populatable from the setup's condition via `Bot.populate_setup_ingredients_from_condition/1` (encouraged → primary, discouraged → avoid). |

A persona (e.g. "Grandma") can back many setups ("Grandma from Crete", "Grandma
from Naxos").

## How a setup reaches generation

`Bot.get_context_for_date/2` resolves the **effective setup** with a
day → week → config cascade (each of `AiBotConfig`, `WeekConfig`, `DayConfig`
carries an optional `recipe_setup_id`). `Bot.build_brief/1` turns the setup into
the keyword brief passed to `RecipeAgent.run/2`:

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

## Files

- Schemas: `apps/mehungry/lib/mehungry/ai/bot/{persona,recipe_setup,recipe_setup_ingredient,recipe_order}.ex`
- Context: `Mehungry.AI.Bot` — persona/setup/order CRUD, `build_brief/1`, `populate_setup_ingredients_from_condition/1`, `get_context_for_date/2`
- Generation: `Mehungry.AI.Agents.RecipeAgent` (`run/2`, `system_prompt/1`, `polish_prose/2`)
- Shared generation helpers: `Mehungry.AI.Bot.RecipeGeneration` (meal prompts, live condition guidance, avoid-guard) — used by both workers
- Workers: `DailyRecipeGenerationWorker`, `RecipeOrderWorker`
- Admin UI: `MehungryWeb.AiBotLive.{Personas,Setups,Orders}` + the setup picker / per-week / per-day override in `AiBotLive.Config`
- Seeds: predefined personas in `apps/mehungry/priv/repo/seeds.exs`
