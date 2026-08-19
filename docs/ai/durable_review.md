# Durable "generate → hold for review → act" (and why not Jido)

Status: **design note.** The bot pipeline already implements this pattern; this
documents it as a reusable primitive and evaluates whether the
[Jido](https://github.com/agentjido/jido) agent framework's durable pause/resume
would add anything. Conclusion: **it wouldn't — we already have durable
pause/resume, on Oban + Ecto, and it fits our shape better.**

## What "durable pause/resume" means here

The appeal of a framework like Jido is being able to **pause a workflow, survive a
restart, and resume it later** — e.g. hold an AI-generated artifact until a human
approves it, without keeping a process alive in the meantime.

There are two different things people mean by this, and the distinction decides
whether we need a framework:

1. **Pause mid-LLM-conversation** — freeze a tool-use loop partway through,
   collect human input, then resume the *same* conversation. This is what Jido's
   session snapshot/resume targets.
2. **Pause between "generated" and "acted-on"** — run the agent to completion
   autonomously, persist its output, and gate the *next side effect* (publish,
   apply to a client) on human approval.

**Our agents are shape (2), not (1).** `RecipeAgent`, `MealPlanAgent`, and
`NutritionistAgent` run to completion in one `AI.Agent.run/6` call and return a
finished artifact. The human reviews the *output*, never a half-finished
conversation. So the mid-conversation snapshot/resume that Jido specializes in
solves a problem we don't have — while adding a framework, a new dependency
surface (`req_llm`/`jido_ai`), and churn against a young (v2.3.x) API.

## We already have durable pause/resume: the bot pipeline

The AI-bot recipe pipeline is exactly a durable "generate → hold → act" workflow,
built from two primitives we already run everywhere:

- **The pause is a DB row + status column.**
  `DailyRecipeGenerationWorker` generates recipes and writes an
  `AiBotRecipe` with `status: "pending_review"`
  (`@valid_statuses ~w(pending_review approved rejected published)` in
  `ai/bot/ai_bot_recipe.ex`). That row *is* the paused state — it survives any
  node restart, deploy, or crash, because it's in Postgres, not in a process.

- **The resume is a gated Oban worker.**
  `RecipePublishWorker` is scheduled (`scheduled_at`) but re-checks the gate at
  run time: `if bot_recipe.status != "approved", do: skip`. Approval happens
  out-of-band in the review LiveViews
  (`professional_live/ai_bot_live/{review_queue,recipe_review}.ex`); the worker,
  when it fires, only acts if the human said yes. A per-platform `"ok"` post-log
  check makes re-publish idempotent, and a manual re-publish passes `force: true`
  to bypass it.

This is more robust than an in-memory framework pause: there is no live process to
lose, the queue is transactional with the data, and Oban already gives retries,
uniqueness, and cron. The "workflow state machine" is just a `status` column plus a
worker that reads it.

## Generalizing it for meal / nutritionist plans (proposed, not built)

Today only the bot pipeline has the review gate. If we want the same durable gate
for user meal plans or nutritionist plans (e.g. a nutritionist reviews an
AI-drafted plan before it lands on a client's calendar), we don't need Jido — we
reuse the same three parts:

1. **A `status` column** on the artifact (`draft → pending_review →
   approved/rejected → applied`) with an `Ecto.Changeset.validate_inclusion`, the
   way `AiBotRecipe` does.
2. **A review surface** — a LiveView listing `pending_review` rows with
   approve/reject actions, mirroring `review_queue.ex`.
3. **A gated action worker** — an Oban worker that performs the side effect
   (persist the plan to the client) and, like `RecipePublishWorker`, re-reads the
   status at run time and no-ops unless `approved`; idempotent on its output.

The key design rule (already followed by the bot pipeline): **the agent's job ends
at "produce and persist a draft."** It never performs the gated side effect
itself. The side effect is a separate, status-gated worker. That separation is
what makes the pause durable — nothing is held in memory across the human step.

### Sketch

```
AgentWorker (Oban)                Review LiveView            ActionWorker (Oban)
──────────────────                ───────────────            ───────────────────
run agent → {:ok, draft}          admin/pro clicks           re-read status;
persist Draft{status:             "approve" →                if != "approved": skip
  "pending_review"}               status="approved"          else apply side effect
(returns; no process held)                                   (idempotent)
```

No supervisor tree of paused agents, no snapshot store, no new framework — just the
Oban + Ecto primitives already in `Mehungry.Application`.

## When Jido *would* be worth revisiting

Only if we move to shape (1): agents that must **stop mid-tool-loop to ask a human
a question and then continue the same reasoning** (interactive co-pilot, multi-turn
approval *inside* one generation). We have no such flow today. If one appears,
re-evaluate then — but weigh it against simply splitting the interaction into
separate `AI.Agent.run/6` calls with a status-gated wait in between, which stays on
the durable Oban+Ecto substrate this note describes.

## Related

- Reliability of the loop itself (accumulator threading, provenance gates,
  telemetry) — see `apps/mehungry/lib/mehungry/ai/agent.ex` and
  `docs/infrastructure/observability.md` (AI agent metrics).
- Bot pipeline overview — see `CLAUDE.md` (AI Bot Pipeline) and
  `docs/ai/ai_bot_personas.md`.
