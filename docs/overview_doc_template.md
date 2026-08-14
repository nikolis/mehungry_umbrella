# Template — Domain Overview ("front-door") Doc

A reusable pattern for the **overview doc that sits at the front of a group of
related docs** and routes a reader into the deep dives. Worked example:
[`ai/ai.md`](ai/ai.md), which fronts the `docs/ai/` folder.

Use this when a topic has grown past one file (a folder like `docs/ai/`, or a
cluster like the scientific-pipeline docs) and a newcomer needs a map before the
detail. One overview per folder/cluster; keep the depth in the linked docs.

## What the pattern is

A short, scannable **index-with-context**. It answers, in order:

1. **What is this** — one or two lines: "front door to `docs/<x>/`", what the
   domain does.
2. **What it does / capabilities** — a table mapping each capability to its entry
   point and the doc that covers it in depth. This is the heart of the page.
3. **Dependencies & configuration** — *external* providers, seams, env keys — the
   things you can't learn from any single deep-dive.
4. **Internal collaborators** — the *other parts of the project* this domain leans
   on (which contexts, and what for). This is the integration surface / blast
   radius, and it's usually the highest-value section: no deep-dive states it, and
   it's what a newcomer needs to place the domain in the whole app. Keep external
   (step 3, "what to configure to run it") and internal (step 4, "what else in the
   app it touches") as separate tables — they answer different questions.
5. **Where the code lives** — a short directory map (deployed vs not, app boundaries).
6. **Cross-cutting principles** — the handful of rules that hold across *every*
   feature in the domain, each linking to where it's elaborated.
7. **Read next** — an annotated index of the sibling docs (one line each on when
   to open it).
8. **Adjacent-but-excluded** (optional) — a one-line pointer to a neighbouring
   topic people confuse with this one, so the scope boundary is explicit.

Not every section is mandatory — drop "Dependencies" if the domain has no external
ones — but keep the order, because readers learn to scan for it.

## Rules that make it work

- **Overview, not detail.** If a paragraph explains *how* something works, it
  belongs in a deep-dive; here you link to it. The page should stay skimmable in
  under a minute.
- **Every row/principle links out.** The value is routing — a capability with no
  link is a dead end.
- **Tables for the capability map**, prose only for the principles. Tables force
  the "capability → entry point → deep dive" triple that makes the map useful.
- **Link relatively.** Siblings in the same folder are `other.md`; docs one level
  up in `docs/` are `../other.md`. (Verify with the resolve check below.)
- **One job: get the reader to the right deep-dive fast.** Resist duplicating
  content — duplication drifts out of sync. When in doubt, link.
- **Keep it current by construction.** Because it only holds pointers + invariants,
  it rarely needs edits; when a new deep-dive is added to the folder, add one row
  and one "Read next" line.

## Skeleton

Copy, then replace `<…>`:

```markdown
# <Domain> — Overview

<One or two lines: front door to `docs/<x>/`; what the domain does.>

## What <domain> does

| Capability | What it produces | Entry point | Deep dive |
|---|---|---|---|
| **<capability>** | <output> | <module/route/worker> | [`<doc>.md`](<doc>.md) |

## Dependencies & configuration        <!-- external; drop if none -->

| Dependency | Used for | Seam | Key |
|---|---|---|---|
| **<provider/lib>** | <what> | `<Module>` | `<ENV_VAR>` |

## Internal collaborators               <!-- other project contexts this domain uses -->

| Context | What <domain> uses it for | Doc |
|---|---|---|
| **<Context>** | <what for> | [`../<doc>.md`](../<doc>.md) |

## Where the code lives

- **`<path>`** — <what's here>.

## Cross-cutting principles

1. **<Principle>.** <One line; link to where it's elaborated.>

## Read next

- [`<doc>.md`](<doc>.md) — <when to open it>.

> Adjacent but not "<domain>": <neighbouring topic> — see [`../<doc>.md`](../<doc>.md).
```

## Verify the links resolve

Run from inside the doc's own directory so relative paths resolve as a reader sees
them:

```bash
cd docs/<folder>
grep -oE '\]\(([^)#]+)(#[^)]*)?\)' <overview>.md | sed -E 's/\]\(([^)#]+).*/\1/' | sort -u \
  | while read p; do [ -f "$p" ] && echo "OK   $p" || echo "MISS $p"; done
```

Every line should read `OK`.
