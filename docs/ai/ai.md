# AI in Mehungry — Overview

How AI is used across the product, who provides it, where the code lives, and the
patterns every AI feature shares. This is the front door to `docs/ai/` — each
section links to the doc that covers it in depth.

## What AI does here

| Capability | What it produces | Entry point | Deep dive |
|---|---|---|---|
| **Recipe generation** | A full validated recipe (ingredients, steps, prose) from a description | Create-recipe LiveView; `DailyRecipeGenerationWorker`; `RecipeOrderWorker` | [`ai_agents.md`](ai_agents.md) · [`ai_bot.md`](ai_bot.md) |
| **Persona-voiced authoring** | Recipes written in a character's voice (grandma, tavern, dietologist) | `RecipeSetup` bound to a config/order | [`ai_bot_personas.md`](ai_bot_personas.md) |
| **Social publishing pipeline** | Review-gated recipes fanned out to IG/FB/Pinterest | `/professional/ai-bot/**` | [`ai_bot.md`](ai_bot.md) · [`../social_publishing.md`](../social_publishing.md) |
| **Meal-plan generation** | A 7-day plan drawn from the user's own recipe catalog | Calendar LiveView (`MealPlanAgent`) | [`ai_agents.md`](ai_agents.md) |
| **Nutritionist plan drafting** | A 7-day plan a pro drafts *for a client*, with a rationale | `NutritionistAgentWorker` | [`ai_agents.md`](ai_agents.md) |
| **Translation** | Recipe + ingredient/unit text in other languages (en/el) | `RecipeTranslator`, `IngredientTranslator` | [`ai_agents.md`](ai_agents.md) |
| **Cover images** | Food-photography image per recipe | `RecipeImageWorker` (OpenAI `gpt-image-1`) | [`ai_agents.md`](ai_agents.md) |
| **Semantic search / embeddings** | pgvector recipe embeddings for meaning-based catalog search | `RecipeEmbeddingWorker`, `RecipeVectorSearch` | [`ai_agents.md`](ai_agents.md) |
| **Measurement extraction** | Compound-measurement candidates pulled from full-text papers by a local QA model | `apps/mehungry_local_ai` → `/api/local_ai/*` | [`measurement_extraction.md`](measurement_extraction.md) |

## Providers & configuration

Two external providers; everything else is our own code.

| Provider | Used for | Client seam | Key |
|---|---|---|---|
| **Anthropic (Claude)** | All text generation, agents, translation, prose polish | `AI.Client` (the *only* Anthropic caller) | `ANTHROPIC_API_KEY` → `:anthropic_api_key` |
| **OpenAI** | Image generation + recipe embeddings (Anthropic offers neither) | `AI.ImageGenerator`, `AI.EmbeddingClient` | `OPENAI_API_KEY` (optional) |

**Models** — the tool-loop runs on **Haiku** (`claude-haiku-4-5-20251001`, cheap/fast
structured tool calling); user-visible prose is rewritten by **Sonnet**; embeddings
use OpenAI `text-embedding-3-small`. Model IDs are currently hardcoded per module
(see the "centralize model IDs" improvement in [`ai_agents.md`](ai_agents.md)).

## Internal collaborators

Contexts the AI layer depends on (facts no single AI deep-dive states — this is the
integration surface and blast radius):

| Context | What AI uses it for | Doc |
|---|---|---|
| **Food** | Ingredient search, recipe create/update, measurement units, `RecipeVectorSearch` | [`../food/food.md`](../food/food.md) |
| **FoodData.Usda** | Real nutrition (`FdcClient`) when creating a missing ingredient, before AI-estimating | [`../food/food.md`](../food/food.md) |
| **Health** | Encouraged/discouraged ingredients for condition-driven setups | [`../science/health_recommendations.md`](../science/health_recommendations.md) |
| **Subscriptions** | Quota-gating user-facing generation (`check_quota/2` · `record_usage/2`) | [`../subscriptions_billing.md`](../subscriptions_billing.md) |
| **Social** | Publishing generated recipes to IG/FB/Pinterest (`Publisher`, `Instagram`, `Pinterest`) | [`../social_publishing.md`](../social_publishing.md) |
| **Accounts** | Bot users + `register_3rd_party_user/1` for new bot identities | [`../users/accounts.md`](../users/accounts.md) |
| **Languages** | Translation targets and localized ingredient/unit display | [`../localization.md`](../localization.md) |
| **Posts** | Creating the social `Post` that backs each generated recipe | — |
| **Oban · S3 · PubSub** | Background execution, image upload, review/progress broadcasts | — |

## Where the code lives

- **`apps/mehungry/lib/mehungry/ai/`** — the deployed AI layer: `AI.Client`
  (HTTP), `AI.Agent` (generic tool-use loop), the three agents
  (`RecipeAgent`, `MealPlanAgent`, `NutritionistAgent`), and single-shot
  utilities. Full anatomy in [`ai_agents.md`](ai_agents.md).
- **`apps/mehungry/lib/mehungry/ai/bot/`** — the recipe→social pipeline domain
  (configs, personas, setups, orders, workers). See [`ai_bot.md`](ai_bot.md).
- **`apps/mehungry_local_ai/`** — a **non-deployed** GPU-box app running the local
  extractive-QA model. It's excluded from the release/Docker build so
  `nx`/`exla`/`bumblebee` never ship to production; it talks to the server only
  over the token-guarded `/api/local_ai/*` REST API. See
  [`measurement_extraction.md`](measurement_extraction.md) and its
  [design review](measurement_extraction_review.md).

## Cross-cutting principles

These hold across every AI feature (elaborated in
[`ai_agents.md` → Design Principles](ai_agents.md#design-principles-summary)):

1. **One HTTP client.** Every Anthropic call goes through `AI.Client` — never raw
   HTTPoison — so auth, retries (529/timeout backoff), and parsing live in one place.
2. **Validate, don't trust.** The DB is the source of truth. Agents get a `submit_*`
   tool that checks every ID against the database and returns actionable errors the
   model must fix before anything is saved — LLMs happily invent plausible IDs.
3. **The submit tool is the only exit.** A run that never submits is a failure, not a
   silent partial save.
4. **Cheap model for the loop, expensive model for the prose** (Haiku → Sonnet).
5. **Degrade gracefully.** Legacy pipelines as fallbacks, best-effort prose polish,
   FTS fallback for vector search, partial plan persistence.
6. **Humans in the loop where it's public.** Bot recipes are **never auto-published** —
   they enter `pending_review` and an admin approves each one. Science candidates are
   review-gated too.
7. **Quotas where it costs.** User-facing generation is gated by subscription tier
   (`Subscriptions.check_quota/2` before, `record_usage/2` after success) — see
   [`../subscriptions_billing.md`](../subscriptions_billing.md).
8. **Real data over generated data.** USDA FDC lookups before AI-estimated nutrition,
   with the `data_source` tagged for audit.

## Read next

- [`ai_agents.md`](ai_agents.md) — the AI infrastructure and agents, in depth (client,
  loop, the three agents, embeddings, Oban wiring, and a running list of improvements).
- [`ai_bot.md`](ai_bot.md) — the recipe→social-media pipeline: admin UI, domain/workers,
  and a review of known issues.
- [`ai_bot_personas.md`](ai_bot_personas.md) — personas, recipe setups, and ad-hoc orders.
- [`measurement_extraction.md`](measurement_extraction.md) — the local QA extraction
  service and its `/api/local_ai/*` contract; [`measurement_extraction_review.md`](measurement_extraction_review.md)
  is the design review.
- [`durable_review.md`](durable_review.md) — the durable "generate → hold for review
  → act" pattern (Oban + `status` column), and why the Jido framework isn't needed
  for it.

> Adjacent but not "AI": the scientific knowledge pipeline (literature crawl,
> PubTator, compound curation) is discovery/curation, not generation — see
> [`../science/scientific_pipeline.md`](../science/scientific_pipeline.md).
