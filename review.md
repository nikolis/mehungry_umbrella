# Mehungry — Code Review: Improvements & Optimizations

_Reviewed: 2026-08-08 · Scope: `apps/mehungry` (domain) + `apps/mehungry_web` (web). This is a
prioritized, actionable list. Each item cites `file:line`. Severity: 🔴 high · 🟠 medium · 🟡 low.
Items marked **(verify)** were found by pattern-scan and should be confirmed before acting._

---

## 1. Correctness / Bugs

### 🔴 Unencoded free-text search breaks routing on special characters
`apps/mehungry_web/lib/mehungry_web/live/recipe_browser_live/index.ex:244`
```elixir
true -> "/search/" <> query_string
```
The `@`-ingredient branch uses `URI.encode/1`, but the plain-text branch does not. A query
containing `/`, `#`, `%`, or `?` (e.g. `50/50 blend`, `c#`) produces a malformed path →
wrong route match or 404. **Fix:** `"/search/" <> URI.encode(query_string)` and confirm the
`:query` route param decodes it.

### 🟠 Dead / unreachable code in the recipe browser
`recipe_browser_live/index.ex`
- The **second `handle_event("search", ...)` clause** (~`:210-239`) can never run: the first
  clause matches the same `%{"recipe_search_item" => %{"query_string" => _}}` shape. Remove it,
  or the `Search.update_recipe_search_item`/`search_recipe` path it references will rot.
- `apply_action(socket, :show, ...)` (~`:428-457`) hard-codes `query_str = ""`, so its
  `case query_str do nil -> ... end` branch is dead. The `:show` action itself may also be
  unreachable (routes only map `:index` / `:show_recipe`) — **(verify)** against `router.ex`.
- The **"Sort Options"** block (`index.html.heex:27-64`) is commented out and `assign(sort_by:
  "recent")` + the `:sort_by` assign have no `handle_event("sort_by", …)`. Either wire it up or
  delete the assign and markup.

### 🟠 `Task.start/1` swallows failures in social publishing
`recipe_details_live/social_media_post_component.ex:78,149,173`
`Task.start` is fire-and-forget: any exception in the publish closure is lost (no result, no
retry, no user feedback). For anything user-visible or that can fail (network/Instagram/Pinterest
calls), prefer an Oban job (already the pattern for `RecipePublishWorker`) or
`Task.Supervisor.async_nolink` + a `handle_info` that surfaces `{:error, _}`.
_(Note: the `Task.async` usages in `create_recipe_live/index.ex` are **correct** — they store the
ref, `Process.demonitor(ref, [:flush])`, and handle `:DOWN`. Leave those.)_

### 🟡 `String.to_atom/1` on dynamic keys — atom-table exhaustion
`apps/mehungry/lib/mehungry/utils.ex:20` (`put_map`), `food/nutrition/nutrient_hierarchy_builder.ex:177,213,701`,
`components/select_component/select_component_deep.ex:152,207`.
Atoms are never GC'd. Where keys can originate from external data (parsed JSON, USDA payloads,
form field names), use `String.to_existing_atom/1` (with a rescue) or keep string keys. Highest
risk is `Utils.put_map/3` if ever fed attacker/-external-controlled maps.

---

## 2. Performance

### 🟠 Browse: per-render condition badge queries on every page + load-more
`recipe_browser_live/index.ex:468-471` (`stream_recipes/3`)
Every stream push calls `RecipeFlags.opted_in_condition_ids/1` then `Health.flags_for_recipes/2`.
On infinite-scroll this fires extra queries per page. Options: (a) compute
`opted_in_condition_ids` once in `mount` and stash in assigns (it can't change mid-session);
(b) ensure `flags_for_recipes/2` is a single grouped query (it is) and short-circuits on empty
opt-ins (it does). Item (a) is the quick win.

### 🟠 Cursor pagination needs a matching composite index
`food/recipes.ex:324-342` paginates with `cursor_fields: [{:inserted_at, :asc}, {:id, :asc}]`
over `where not is_nil(image_url)`. Confirm an index on `recipes (inserted_at, id)` (partial on
`image_url IS NOT NULL` is even better) exists — otherwise every browse page does a sort. The new
`Health.recipes_for_conditions_query/1` composes on top of this, so it inherits the same need.
**(verify** against `priv/repo/migrations`).

### 🟠 Write-side N+1 in `set_condition_opt_ins/2`
`accounts/profiles.ex:101-117` inserts opted-in conditions one-by-one (`Repo.insert!` per id in a
loop). Replace the insert loop with a single `Repo.insert_all/3` (keep the transactional
delete-then-insert diff). Low volume today, but it's the idiomatic fix.

### 🟡 Analytics/visit tracking is query-heavy
`apps/mehungry/lib/mehungry/meta.ex` (660 lines, ~20+ `Repo.all`) builds dashboards with many
unbounded `Repo.all`. As `visits` grows this will slow the dashboard and hold connections. Add
explicit `limit`/date-window bounds, push aggregation into SQL (`group_by`/`count`), and consider
materialized rollups (the `Telemetry.MetricsBuffer` snapshot pattern is a good precedent).

### 🟡 Unbounded `Repo.all(Schema)` loads
e.g. `inventory.ex:27,242`, `subscriptions.ex:181 (Repo.all(UserSubscription))`,
`food/nutrients.ex:41`. Fine while tables are small; add `limit`/filters (or paginate) before
these tables grow. Flagging as a class, not each call.

### 🟡 Leftover debug output on a hot path
`usda/corpus/TFIDF.ex:28-29` has `IO.inspect(..., label:)` — remove. Broader: ~20 `IO.puts`/
`IO.inspect` in `apps/mehungry/lib` (mostly maintenance tasks/`release.ex`, which are acceptable,
but the TFIDF and nutrition `print_*` debug helpers should use `Logger` or be dropped).

---

## 3. Best Practices / Maintainability

### 🟠 Very large modules — split by responsibility
`meta.ex` (660), `food/nutrition/nutrient_hierarchy_builder.ex` (708), and
`create_recipe_live/index.ex` (500+) are hard to test and reason about. The umbrella already
favors focused sub-modules behind facades (`Food.*`, `Accounts.*`) — extract cohesive slices
(e.g. `Meta.Reports`, `Meta.Ingest`) and keep the public facade stable.

### 🟠 `System.get_env` read at request time in LiveView
`create_recipe_live/index.ex` reads `SPOONACULAR_API_KEY` inside `handle_event`. Per the project
convention (secrets resolved in `runtime.exs` into `config`), move this to
`Application.get_env(:mehungry, :spoonacular_api_key)` set once in `runtime.exs`, matching how
`FDC_API_KEY`/`ANTHROPIC_API_KEY` are handled. Also note `SPOONACULAR_API_KEY` isn't documented in
CLAUDE.md's env list — add it.

### 🟡 Consistency of the HTTP-client seam
Several modules use HTTPoison directly (`chemistry/pubchem/client.ex`, `food_data/usda/fdc_client.ex`,
`social/facebook.ex`, `social/pinterest.ex`, `billing/stripe_handler.ex`, `meta.ex`,
`ai/embedding_client.ex`). That's acceptable (each is a typed client), but they duplicate
retry/backoff/timeout logic that `AI.Client` already solves well. Consider a shared HTTP helper
(auth + exponential backoff + JSON decode) to standardize error handling across external calls.

### 🟡 `@impl true` and clause grouping
The new/edited `handle_event` clauses in `recipe_browser_live` are fine, but the module mixes
`@impl true` presence; and `list_recipes/1`/`/2` clauses in `food/recipes.ex` triggered
"clauses should be grouped together" compiler warnings. Group same-name clauses and keep `@impl`
consistent to keep the build warning-clean.

---

## 4. Security

### 🟠 Confirm authZ on `/professional/**` and `/nutritionist/**` end-to-end
Routing uses `on_mount` (`AdminAuthLive`, `NutritionistAuthLive`) and `RequireAdmin`. Verify every
LiveView under those live_sessions actually enforces it (a LiveView added to the wrong session
silently loses its gate). Spot-check `professional_live/*` and the `/api/local_ai/*` token guard.

### 🟡 Owner-email quota bypass is a string compare
`Subscriptions` bypasses quota for `nikolisgal@gmail.com`. Ensure the comparison is against the
**canonical** email (the app already has `canonical_email` dedupe) so an alias/case variant can't
be exploited, and that it's not spoofable via unconfirmed accounts.

---

## 5. Testing

- 🟠 **Stream-reset assertions**: `LiveViewTest` does not reflect `stream(reset: true)` *removals*
  in the rendered DOM (discovered while adding the condition filter). Existing/ future tests that
  assert "item disappeared after filter" via the stream will give false confidence — assert via a
  structural change (empty-state swap) or the underlying query instead. Document this in the test
  helpers so others don't trip on it.
- 🟡 **Coverage gaps** worth adding: `meta.ex` report queries, `RecipeSearch.run/2` prefix/synonym
  normalization, and the `Task`-based async flows in `create_recipe_live` (success + `:DOWN`).

---

## 6. Quick Wins (low effort, clear value)

1. `URI.encode` the plain-text search path (`recipe_browser_live/index.ex:244`). 🔴
2. Delete the unreachable `handle_event("search", …)` 2nd clause + dead `:show`/`sort_by` code. 🟠
3. Compute `opted_in_condition_ids` once in `mount` for the browse stream. 🟠
4. Remove `IO.inspect` in `usda/corpus/TFIDF.ex:28-29`. 🟡
5. Move `SPOONACULAR_API_KEY` into `runtime.exs` config + document it. 🟡
6. `Repo.insert_all` in `set_condition_opt_ins/2`. 🟡

---

### Notes on method
Findings are from targeted static scans (grep patterns for `Repo.all` without bounds, N+1 shapes,
`Task`/`spawn`, `String.to_atom`, HTTP clients, dead clauses) plus reading the browse/search/health
paths in depth. I did **not** exhaustively read every module; items tagged **(verify)** are
higher-uncertainty. No runtime profiling was performed — performance items are structural, not
measured. Good existing patterns worth preserving: the `Food`/`Accounts` facade convention, the
typed `AI.Client` retry layer, Oban queue separation, and the DIY telemetry snapshot store.
