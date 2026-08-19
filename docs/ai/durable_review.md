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
the durable Oban+Ecto substrate this note describes. The section below assesses
that shape-(1) move in full.

## Assessment: mid-tool-loop human-in-the-loop (shape 1)

Would it produce better results, can we do it with current models, what would have
to change, and what does it cost? Findings, grounded in our actual stack (Haiku-4.5
agents, a Sonnet writer, the `AI.Agent` loop that already re-sends full history each
turn).

### Would it produce better results?

Only in **one** of the three agents, and even there the gain is modest. The quality
win of pausing mid-loop (vs. "generate full draft → human edits → regenerate") comes
from preserving the model's *accumulated reasoning*. That matters when the reasoning
is deep and multi-step; ours mostly isn't:

- **RecipeAgent** — runs unattended (`DailyRecipeGenerationWorker`, 2am). No human is
  present to ask. Zero benefit.
- **MealPlanAgent** — user-facing, but shallow reasoning (search → assemble →
  validate). The user can just regenerate; mid-loop buys little over draft-then-revise.
- **NutritionistAgent** — **the real case.** A professional steering a draft as it is
  built ("client hates fish, swap dinner day 3; keep the breakfasts") is genuinely
  better mid-loop: full context preserved, wrong direction corrected early rather than
  after 21 meals are assembled, and the human is already engaged live. A premium,
  interactive co-pilot UX where preserved context earns its keep.

**Conclusion:** worth it for the nutritionist co-pilot; not worth it for the other two.

### Can we do it with current models?

**Yes — no model change, no capability gap; it works on Haiku today.** The Anthropic
Messages API is **stateless**: "pause to ask a human" is architecturally identical to
a tool call whose result comes from a person instead of a function. The model does not
stay alive between turns — **the conversation _is_ the state.** We serialize the
message list, wait minutes/hours/days, then resume by appending the human's answer as
a `tool_result` and calling the API again. The blocker was never the model; it is our
architecture.

### What would have to change?

`AI.Agent.run/6` is synchronous, in-memory, and runs to completion. Shape (1) needs it
to **suspend and resume across durable time**:

1. **Serialize conversation state.** Today `messages` lives only in the Oban worker
   process. Persist `{messages, system, tools, model, acc}` to a DB row (JSONB) when a
   pause fires. *This is the actual work.*
2. **An `ask_human` tool** that suspends the loop instead of dispatching — the loop
   returns `{:suspended, state}` rather than continuing.
3. **A resume entry point** — `Agent.resume(state, human_answer)` appends the answer as
   a `tool_result` and re-enters the loop.
4. **Durable storage + UI** — an `agent_sessions` table (`status: running |
   awaiting_human | done`, serialized messages) plus a LiveView to show the pending
   question and submit the answer, which enqueues the resume. Same shape as the
   review-gate pattern above, but the paused state is a *whole conversation*, not just
   an output row.
5. **Staleness handling** — a recipe/ingredient the paused plan references may be
   deleted before resume. Our existing provenance/validation gates absorb most of this.

That is essentially a durable conversation-workflow engine on Oban + Ecto. **This is
the one scenario where "buy instead of build" is real:** Anthropic **Managed Agents**
is precisely this — server-hosted sessions that pause on a tool-confirmation /
custom-tool-result and resume from a durable event stream. It would offload the
serialize/resume plumbing, but it hosts the agent loop on Anthropic's side, colliding
with our custom `AI.Client`/`AI.Agent`. Prefer building on Oban + Ecto for consistency;
only revisit Managed Agents if the plumbing proves heavier than expected.

### Cost implications

**Token cost is negligible; the real costs are latency and engineering.**

- **Why tokens grow:** the stateless API re-bills the *entire prior conversation* as
  input on every resume. Our loop already does this per iteration (inherent to any
  tool-use loop); human turns just add more full-context turns as the conversation grows.
- **The numbers:** on **Haiku 4.5 ($1/M input, $5/M output)** a recipe/meal-plan run is
  tens of thousands of cumulative input tokens + a few thousand output → **fractions of
  a cent**. Adding 3–4 human interrupts is ~1.5–2× that → still fractions of a cent.
  Upgrading the *interactive* co-pilot to **Sonnet 5 ($3/M in, $15/M out)** for better
  judgment is ~3× per token — still a small absolute number.
- **The caching trap:** cache reads cost ~0.1× and writes 1.25×, but the **default cache
  TTL is 5 minutes**. A human usually answers *after* 5 minutes, so the cached prefix
  expires before the resume → the resume pays **full-price cold input** again. Use the
  **1-hour TTL** (2× write cost) to keep the system-prompt + tools + early-conversation
  prefix warm across a reviewer's think-time. Over *days*, no caching helps and each
  resume pays cold input — still cents on Haiku/Sonnet.
- **What actually bites:** **latency and operational surface.** A 30-second background
  job becomes a multi-minute-to-hours interactive session with durable state, a review
  UI, and staleness edge cases. Engineering and UX cost, not API cost.

### Recommendation

Scope it to the **NutritionistAgent** as an interactive co-pilot, **build on Oban +
Ecto** (extending the review-gate pattern above), and use the **1-hour cache TTL** on
resumes. Do not retrofit it onto RecipeAgent (unattended) or MealPlanAgent (marginal).
It is an architecture change, not a model upgrade — and on our token economics the cost
is dominated by latency and engineering, not the API bill.

## Related

- Reliability of the loop itself (accumulator threading, provenance gates,
  telemetry) — see `apps/mehungry/lib/mehungry/ai/agent.ex` and
  `docs/infrastructure/observability.md` (AI agent metrics).
- Bot pipeline overview — see `CLAUDE.md` (AI Bot Pipeline) and
  `docs/ai/ai_bot_personas.md`.
