# AI Bot

The automated recipe→social-media pipeline: monthly (or ad-hoc) config →
AI recipe generation → admin review → translation → scheduled/manual publish to
Instagram/Facebook/Pinterest. This doc covers the **whole subsystem** — the
LiveView admin surface, the domain/worker pipeline behind it, and a
[review of known issues](#review--known-issues).

Related docs: [`ai_bot_personas.md`](ai_bot_personas.md) (persona/setup/order
domain model), [`social_publishing.md`](../social_publishing.md) (the publish
fan-out). CLAUDE.md's "AI Bot Pipeline" section is the one-paragraph overview.

## Pipeline at a glance

```
DailyRecipeGenerationWorker (cron 2am UTC, or manual "Generate now")
  └─ resolve config (setup_type: theme | condition)
  └─ per meal_type: RecipeAgent.run(description, brief_opts)   [avoid-guard retry]
  └─ persist Recipe + Post + AiBotRecipe(pending_review)
  └─ schedule RecipePublishWorker per (meal × language) at publish_times
        │
   admin review  (/professional/ai-bot/review)  → approve / edit / translate
        │
   RecipePublishWorker (status must be "approved")
  └─ Social.Publisher.publish_recipe/5 → per-platform SocialMediaPostLog
  └─ mark_published when all configured languages are logged

RecipeOrderWorker (ad-hoc "N recipes for a setup", bot_config_id: nil)
  └─ same generation + avoid-guard, lands in the same review queue (manual publish only)
```

Key domain modules: `Mehungry.AI.Bot` (facade/context), schemas under
`Mehungry.AI.Bot.*`, `Mehungry.AI.Agents.RecipeAgent` (tool-use generation +
persona-voiced prose polish), workers under `Mehungry.ObanWorkers.*`
(`:ai_agents` queue for generation/translation, `:default` for publishing).

## Admin web UI

LiveViews under `apps/mehungry_web/lib/mehungry_web/live/professional_live/ai_bot_live/`,
all in the `:default2` (`AdminAuthLive`) session at `/professional/ai-bot/**`,
talking to the domain through the `Mehungry.AI.Bot` facade. Dark slate/`primary`
Tailwind palette; each module carries a local `input_class/0` helper.

### Screen map

| Module | Route(s) | Responsibility |
|---|---|---|
| `AiBotLive.Config` | `/professional/ai-bot`, `/new`, `/:id/edit` | Monthly config CRUD + week/day overrides |
| `AiBotLive.ReviewQueue` | `/professional/ai-bot/review` | The generated-recipe queue: filter, generate, import untracked |
| `AiBotLive.RecipeReview` | `/professional/ai-bot/review/:id` | Single recipe: approve/reject, inline edit, publish modal |
| `AiBotLive.RecipeTranslate` | `/professional/ai-bot/review/:id/translate/:lang` | Side-by-side EN→lang recipe + ingredient/unit translation |
| `AiBotLive.Personas` | `/professional/ai-bot/personas`, `/new`, `/:id/edit` | Authoring-voice CRUD |
| `AiBotLive.Setups` | `/professional/ai-bot/setups`, `/new`, `/:id/edit` | Setup CRUD + seed ingredients |
| `AiBotLive.Orders` | `/professional/ai-bot/orders`, `/new` | Ad-hoc "generate N recipes for a setup" |
| `AiBotLive.SocialAccounts` | `/professional/ai-bot/social` | Per-bot-user IG/FB/Pinterest status + per-language targets |

### Config (`AiBotLive.Config`)

The hub. Left column streams `Bot.list_bot_configs()`; right panel is the
create/edit form.

- **Setup type** toggles the form: `"theme"` (Month → Week → Day themes) vs.
  `"condition"` (pick a `Health.Condition` that already has recommendations +
  free-text `diet_direction`).
- **Persona / Setup** binds an active `RecipeSetup` (`recipe_setup_id`) to give
  every recipe this month a character voice; week/day overrides can swap it.
- **Bot user** picker with an inline "New User" modal →
  `Accounts.register_3rd_party_user/1` (creates + confirms a bot account).
- **Publish times** grid: a `<input type="time">` per (meal_type × language),
  posted as `ai_bot_config[publish_times][meal][lang]`, defaulting to
  `AiBotConfig.default_time_for/1`.
- **Edit-only sub-forms** (separate `phx-submit`s, not the main changeset):
  - `save_week_themes` — weeks 1–6, each an optional theme + setup override;
    blank theme deletes the `WeekConfig`.
  - `save_day_config` / `delete_day_config` — per-date `focus_hint` + optional
    setup override (`DayConfig`).
- **Social status** pills (edit mode) read the bot user's IG/FB/Pinterest tokens;
  detail helpers `facebook_pages_summary/1`, `pinterest_boards_summary/1`.
- Delete is guarded: a config with existing recipes returns `{:error, _}` and
  flashes "Cannot delete configuration with existing recipes."

### Review Queue (`AiBotLive.ReviewQueue`)

- Subscribes to PubSub `"admin:bot_recipes"`; a `{:pending_count_updated, _}`
  message clears the "generating" spinner and reloads.
- **Status filter** tabs: `pending_review` / `approved` / `rejected` /
  `published` / `all`. Recipes are grouped by `scheduled_date` and sorted.
- **Generate now** enqueues `DailyRecipeGenerationWorker` for a chosen
  `bot_config_id` + `target_date`; requires a config to exist.
- **Untracked recipes** lane (pending filter only): recipes authored by the bot
  user that aren't tracked as `AiBotRecipe`s — `import_one` (into the active
  month's config for a matching meal/date slot) or `dismiss_one`.
- Inline `approve` / `reject` from the row; "Review" link opens `RecipeReview`.

### Recipe Review (`AiBotLive.RecipeReview`)

- Status-driven action panel: pending → approve/reject; approved →
  "Publish Now…" + undo; rejected/published → undo/terminal note.
- **Inline edit** (`toggle_edit`) reuses the recipe form machinery —
  `IngredientComponent` + `StepComponent`, `add/remove` ingredient/step events,
  `Food.update_recipe/2`.
- **Publish modal** (`publish_now` → `confirm_publish`): builds per-language
  platform defaults from `config.publish_times`, the bot user's tokens, FB pages,
  and Pinterest boards (a stale-token board fetch failure disables Pinterest).
  Works for both calendar and ad-hoc **order** recipes — the owning bot user comes
  from `Bot.owner_bot_user_id/1` (config **or** order), and order recipes (no
  config) fall back to the order's language with empty target maps. Confirm
  enqueues one `RecipePublishWorker` per language with the selected platforms and
  **`force: true`** (a manual publish may intentionally re-post a platform that
  already logged "ok"). Alpine `x-data` (`publish_xdata/1`) drives the per-language
  checkboxes.
- **Translations** panel: per language, either an "AI" button
  (`trigger_translation` → `RecipeTranslationWorker.enqueue/2`) or a manual link
  into `RecipeTranslate`.

### Recipe Translate (`AiBotLive.RecipeTranslate`)

Side-by-side EN (read-only) vs. target-language editor.

- `retranslate` runs `AI.RecipeTranslator.translate_recipe/2` async
  (`send(self(), :do_translate)`), prefilling the form for review — it does not
  auto-save.
- `save_translation` upserts a `RecipeTranslation` (title/description/steps,
  steps parsed positionally against the original).
- `save_ingredient_translations` upserts ingredient + measurement-unit
  translations via `Food.upsert_ingredient_translation/3` /
  `Food.upsert_measurement_unit_translation/3`.

### Personas / Setups / Orders

Thin CRUD LiveViews over the [personas domain](ai_bot_personas.md):

- **Personas** — name, archetype, description, `voice_prompt` (second person),
  `default_origin`, `uses_hashtags`, `active`. Delete is immediate.
- **Setups** — name, persona, `origin`, `story`, optional `condition_id`,
  `diet_direction`, `active`; a second card (edit mode) manages **seed
  ingredients** with roles (primary/garnish/spice/avoid) via
  `Food.IngredientSearch.search/1`, plus "Populate from condition"
  (`Bot.populate_setup_ingredients_from_condition/1`).
- **Orders** — pick setup + bot user + quantity + optional meal type + language,
  `create_recipe_order` then enqueue `RecipeOrderWorker`; results land in the
  review queue. Cards show `completed_count/quantity` and a status pill.

### Social Accounts (`AiBotLive.SocialAccounts`)

Scoped to the **active config's bot user** for the current month.

- Connection-status cards for Instagram / Facebook / Pinterest with Connect /
  Reconnect links to `/auth/bot/target/:bot_user_id/:provider`
  (`BotOAuthController`). IG status via `Social.Instagram.token_status/1`.
- `fetch_boards/1` distinguishes an auth failure (`:fetch_failed` → surface
  "reconnect") from a genuinely empty board list (→ "create your first board").
- Per-language **Facebook page** and **Pinterest board** selectors persist to
  `config.facebook_page_ids` / `config.pinterest_board_ids`
  (`save_facebook_pages`, `save_pinterest_boards`, blanks stripped).
- `create_pinterest_board` → `Social.Pinterest.create_board/2`.

## Domain & workers

| Module | Role |
|---|---|
| `Mehungry.AI.Bot` (`ai/bot.ex`) | Context/facade — config, bot-recipe, week/day, persona, setup, order, translation, post-log CRUD + `get_context_for_date/2`, `build_brief/1`, `owner_bot_user_id/1` |
| `AI.Bot.AiBotConfig` | Monthly config; `setup_type` theme\|condition, `publish_times` (normalized to `HH:MM:SS`), per-language `facebook_page_ids`/`pinterest_board_ids` |
| `AI.Bot.AiBotRecipe` | The tracked recipe row; status `pending_review → approved/rejected → published`; belongs to **either** a `bot_config` **or** a `recipe_order` |
| `AI.Bot.RecipeOrder` | Ad-hoc "N recipes for a setup" request; `pending/generating/completed/failed` + `completed_count` |
| `AI.Bot.{Persona,RecipeSetup,RecipeSetupIngredient}` | Authoring voice + place/story/condition bundle + roled seed ingredients — see [`ai_bot_personas.md`](ai_bot_personas.md) |
| `AI.Bot.{WeekConfig,DayConfig}` | Optional per-week/per-day theme + setup overrides |
| `AI.Bot.RecipeTranslation` | Per-language title/description/steps; `status` `ai_draft`\|`verified` (default `verified`) |
| `AI.Bot.SocialMediaPostLog` | Per-(platform,language) publish outcome `ok`\|`error`\|`skipped` |
| `AI.Agents.RecipeAgent` | Tool-use generation loop (`search_ingredient`/`create_ingredient`/`submit_recipe`) + persona-voiced prose polish (`@writer_model` = sonnet). `system_prompt/1` leads with the **cuisine** (`cuisine_block/1`), forces "commit to one real named dish first", and injects the `@culinary_rules` realism guardrails (see below) |
| `DailyRecipeGenerationWorker` | Cron 2am UTC + manual generate; per-meal generation, avoid-guard, schedules publish jobs |
| `RecipeOrderWorker` | Fulfils an order; same generation + avoid-guard, no publish scheduling |
| `RecipePublishWorker` | Per-(meal,language) publish via `Social.Publisher`; idempotent through `SocialMediaPostLog` |
| `RecipeTranslationWorker` | AI translation into `recipe_translations` |

The **avoid-guard** (`generate_avoiding/N` in both generation workers) is the hard
safety net: after generation it rejects+retries (≤3×) any recipe containing a
condition-discouraged or seed-`avoid` ingredient **by ingredient_id**, not by
trusting the prompt.

**Cuisine-first realism** is the *soft*, prompt-level counterpart to the hard
avoid-guard, and the primary lever for output that reads as human-authored:

- **Cuisine leads the prompt.** `Bot.setup_cuisine/1` (explicit setup field, else
  derived from `origin`) is stated first and loudest via `cuisine_block/1`; every
  ingredient must be authentic to it, and **fusion is forbidden unless explicitly
  requested**.
- **Commit to a real dish first.** Step 1 forces the model to name one real,
  traditional dish of the cuisine *before* listing ingredients — anchoring on the
  model's own knowledge instead of an external recipe DB (see
  [`ai_bot_personas.md` §Why not TheMealDB`](ai_bot_personas.md#why-not-themealdb)).
- **`@culinary_rules`** enforce restraint: cuisine-appropriate pairings, one main
  protein unless traditional, no gratuitous fruit/novelty, ~5–12 primary
  ingredients, "if uncertain, omit." The old counterproductive "full flavour
  profile" and purple-prose instructions were removed — **from both generation
  and the final prose polish** (`generic_polish_system_prompt` was rewritten to a
  plain-spoken cook voice; the persona path already spoke in-character).
- **Cuisine-styled images.** The resolved cuisine is persisted to the recipe's
  `cousine` column and drives `ImageGenerator.generate/3` (`cuisine_setting/1`),
  replacing the hardcoded warm/rustic "amber" look every cover image used to share.

Unlike the avoid-guard none of this is id-enforced; it applies on **every**
generation (persona or not, daily or order) since both paths run
`RecipeAgent.run/2`.

## Review — known issues

Findings from an end-to-end review (2026-08-14; open issues re-verified still
present 2026-08-15). Ranked by severity.

### ✅ Fixed — publishing an ad-hoc *order* recipe crashed

Order recipes are created with `bot_config_id: nil` (`recipe_order_worker.ex:96`),
and by design are "approved/published **manually** from the review queue" — so
manual publish is their intended path. But that path dereferenced the nil config:
`recipe_review.ex` `publish_now` and `recipe_publish_worker.ex` `publish_platforms`
both read `config.bot_user_id`, and `get_bot_recipe!/1` didn't preload
`:recipe_order`, so there was no fallback.

Fixed (2026-08-14): `get_bot_recipe!/1` now preloads `:recipe_order`;
`Bot.owner_bot_user_id/1` resolves the owner from `bot_config` **or**
`recipe_order`; the LiveView and worker derive per-language targets from the
config when present and fall back to the order's language / empty target maps
otherwise; `maybe_mark_published/2` has a nil-config clause. Regression test:
`recipe_publish_worker_test.exs` "publishes an ad-hoc order recipe that has no
bot_config".

### ✅ Fixed — ingredient-ID resolution put the wrong ingredients in the recipe

**Symptom** (found eyeballing cuisine-first output, 2026-08-15): a generated
**Cacio e Pepe** whose dish name, prose and quantities were perfect but whose
ingredients resolved to *"DOMINO'S 14" Cheese Pizza"* (should be Pecorino) and
*"Beef, ground, patty"* (should be black pepper) — despite the log showing it had
just created "Pecorino Romano cheese" and "black pepper ground". Same class as an
earlier run resolving "bay leaf" → "black tea". The dominant quality problem once
dish selection and prose were good: recipes read authentically but the ingredient
list could be garbage.

**Root cause** (the original write-up misdiagnosed this as the tool loop
"mis-tracking ids" — it does not). `AI.Agent` threads `tool_use_id` and JSON-encodes
each result correctly, so the model *receives* the right ids. The defect was that
`submit_recipe` validation (`validate_recipe`/`check_ingredient_unit`,
`recipe_agent.ex`) was **existence-only**: it checked the `ingredient_id` exists and
the unit is valid *for it*, with **no binding to what the model actually searched**.
With ~100k rows almost any integer "exists", so a hallucinated or cross-wired id
sailed through. The tell: `search/2` excludes `Branded` rows
(`ingredient_search.ex:210`), so "DOMINO'S Pizza" / "Beef, ground, patty" could
**never** have been returned by `search_ingredient` — proving the model supplied an
id it was never handed, and nothing caught it.

**Fix** (2026-08-15): two provenance gates in `submit_recipe`, both feeding the
existing self-correction loop (prompt step 7):
1. `submit_recipe`'s `recipe_ingredients` now carry a required **`name`** (the
   ingredient the model *intends*).
2. The agent records every id→name it hands back (`remember_offered/2`, kept in the
   process dict alongside the smuggled result). `check_provenance/3` rejects any
   `ingredient_id` **never offered this run** (catches hallucinated ids like the
   Domino's case) and any id whose **name disagrees** with the offered candidate
   (`name_matches?/2`, catches two offered ids swapped between ingredients). The
   name check is deliberately lenient (substring / word-level jaro ≥ 0.8) so USDA
   name variants ("pecorino" vs "Cheese, pecorino romano") don't cause resubmit
   thrash. Regression test: `recipe_agent_provenance_test.exs`.

This also hardens the id-based **avoid-guard**: a wrong id could previously let a
discouraged ingredient slip in (or dodge the guard) under an unrelated id. Still
*coupled* to the iteration-thrash item below (more redundant searches → more ids the
model can cite wrongly), but the wrong id can no longer reach a saved recipe.

### 🟠 Medium

**Specialty-cuisine iteration thrash → `:max_iterations_reached`.** Cuisine-first
authenticity makes the agent chase DB-novel ingredients; for e.g. Japanese it fires
near-duplicate `create_ingredient` calls for the *same* item (mirin → "mirin sweet
rice wine" → "rice wine"; panko → "panko crumbs" → "bread crumbs"; dashi → "dashi
kombu and bonito" → "fish stock"), exhausting the loop before `submit_recipe`.
`max_iterations` was bumped **10 → 14** (`recipe_agent.ex:~124`), which lets normal
cases (Italian) finish but **does not rescue the thrashy specialty case** — Japanese
still failed at 14. The real fix is reducing the thrash (dedupe/limit
create-attempts per logical ingredient), or a larger stopgap bump (18–20). Coupled
to the (now fixed) id-resolution item above — fewer redundant searches also means
fewer ids the model can cite wrongly.

**Hashtags land inline in the description with an empty `hashtags` array.** Seen on
both Katsudon and Cacio e Pepe generic-voice runs: the description ends with
`#pasta #italian …` while `attrs["hashtags"]` is `nil`/empty. The polish step's
hashtag separation (put them in the array, not the prose) isn't taking effect on the
generic path. Either the polish JSON isn't being merged back, or the raw generation
description (whose `hashtag_directive` inlines them) is what survives.

**Auto-publish silently no-ops if approval is late.** `schedule_publish_jobs`
(`daily_recipe_generation_worker.ex:199`, enqueue at `:209`) enqueues publish jobs
with `scheduled_at` at *generation* time regardless of approval; at run time the
worker gates on `status != "approved"` and returns `:ok` with no retry/reschedule
(`recipe_publish_worker.ex:23-28`). If the admin approves *after* the scheduled
time, the recipe never auto-publishes — it must be published manually. Consider
re-enqueuing publish jobs on `approve_recipe`, or surfacing the window in the UI.

**Translation "verify" is a no-op.** `RecipeTranslationWorker` writes
`status: "ai_draft"` with a comment that a human verifies it in the hub
(`recipe_translation_worker.ex:32`), but `RecipeTranslate.save_translation` upserts
**without** `status` (`recipe_translate.ex:71-77`), so an existing `ai_draft` stays
`ai_draft` after a human edits it, and nothing consumes the distinction. Either set
`status: "verified"` on manual save, or drop the field.

### 🟡 Low

- **Cuisine only reaches generation through a bound setup.** Theme-only
  `AiBotConfig`s (no `RecipeSetup`) generate cuisine-less, and `derive_cuisine/1`
  is a shallow ~15-country heuristic. Both are deliberate scope boundaries — see
  [`ai_bot_personas.md` §Known limitations (cuisine)](ai_bot_personas.md#known-limitations-cuisine).
- **`dismiss_untracked_recipe` collides on the unique index** (`bot.ex:161`): it
  hardcodes `meal_type: "lunch"` (`:165`) + `scheduled_date: today`, so dismissing a *second*
  untracked recipe the same day violates
  `unique_constraint([:bot_config_id, :meal_type, :scheduled_date])` → UI shows
  "Could not dismiss recipe." Related: `import_single_recipe` can only place ≤5/day
  (one per meal slot) before erroring. A dedicated "dismissed" flag would be cleaner
  than reusing a rejected `AiBotRecipe` row.
- **Language-casing mismatch** (`recipe_review.ex:100`): the publish-language fallback
  is `["en"]` (lowercase) while recipes are created as `"En"` and translations key on
  `lang.name`; the base-language publish target can mismatch.
- **`maybe_mark_published` over-eager on the config path** (`recipe_publish_worker.ex:137`):
  when a meal has no `publish_times`, `languages == []` and `all_languages_published?(_, [])`
  is `true`, so one manual publish flips the recipe to `published`. Harmless but loose.
  The nil-config (order) clause (`:125`) was since hardened with a `languages != []`
  guard; the config clause still lacks it.

### ✅ Solid

- Avoid-guard retry enforces discouraged/`avoid` ingredients by id, not by trusting
  the prompt.
- Idempotent publishing: `platforms_successfully_posted` + `force` prevent
  double-posts across Oban retries; the worker returns `{:error, …}` to *use* Oban's
  retry rather than swallowing failures.
- `publish_times` normalization (`ai_bot_config.ex:80`) coercing `"HH:MM"`→`"HH:MM:SS"`
  closes a whole class of silent scheduling failures from `<input type="time">`.
- Pinterest stale-token vs. empty-list distinction (`social_accounts.ex:47`).
- Condition setups carry benefit via encouraged/`avoid` ingredient lists rather than
  asking the model to "treat a disease".
