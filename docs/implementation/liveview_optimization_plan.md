# LiveView Optimization Plan

**Status:** In progress · **Started:** 2026-10-28 · **Owner:** nikolisgal@gmail.com

A systematic optimization pass over the app's high-level LiveViews. Breadth-first
triage first, then depth-first per-view fixes in ranked order. This doc is the
**resumable source of truth** — any session picks up from the Progress Tracker below.

## Goal & scope

Optimize across **four dimensions at once** (per view):

1. **Runtime performance** — DB work in `mount` (blocks first paint), N+1 queries,
   oversized `assigns`, lists rendered without `stream`/`temporary_assigns`, missing
   `connected?/1` guards on heavy loads.
2. **Code health / maintainability** — break up god-modules, enforce the View/Update
   separation convention (CLAUDE.md "LiveView Conventions"), push direct `Repo.` calls
   out of the web layer into contexts.
3. **REST↔LiveView parity** — find calculations duplicated between a LiveView and its
   `/api/v1` equivalent that can silently drift; collapse to one shared context function
   (see `feedback_rest_liveview_parity` memory + CLAUDE.md "REST ↔ LiveView parity").
4. **Frontend payload / assets** — large static render diffs, data that should be lazy,
   JS hooks, bundle weight.

**Tier order (from `router.ex` `live_session`s):**

| Tier | Session | Priority | Covered in this pass? |
|---|---|---|---|
| Public / anonymous | `:default3`, `:maybe` | Highest (SEO + traffic) | ✅ Phase 0 |
| Consumer authed | `:default` | High | ✅ Phase 0 |
| Nutritionist | `:nutritionist` | Medium (strategic, low volume) | ⏭ later sweep |
| Admin / professional | `:default2` (~40 tools) | Low (single operator) | ⏭ later sweep |

## ⛔ SEO guardrail — HARD GATE on every public-tier change

`docs/growth/seo.md` documents an invariant that is **directly in tension with the most
obvious performance optimization**. A naive "make it async for speed" change will destroy
organic ranking. Every change to a public LiveView must pass this gate before it ships:

1. **Never move rankable content or internal `<a href>` links from synchronous render into
   `assign_async`.** Only the disconnected HTTP render is indexed by Googlebot; async
   assigns render as loading skeletons on the dead render and are invisible to crawlers.
   This is exactly what pinned condition pages to position ~80. If a public page needs
   async for live snappiness, it **must** keep the `connected?/1` split — `assign_async`
   for the live client, synchronous `AsyncResult.ok(...)` for the dead render (see the
   `load_data/2` pattern in seo.md "How Phoenix LiveView interacts with SEO").
2. **Preserve the SEO assigns** set in `mount`/`apply_action`: `page_title`,
   `page_description`, `:canonical_path`, `:structured_data`, OG/`og_image` assigns.
3. **JSON-LD parity** — nutrition in JSON-LD must keep reusing
   `NutrientUtils.macro_summary/1` (same parity rule as REST). A dedup refactor must not
   fork it.
4. **Do not re-expose condition pages**, and do not touch `noindex_prefixes` or the
   canonical/hreflang generics in `head.html.heex`.

**SEO-sensitive public views — audit `connected?/1` before AND after touching:**

- `species_detail_live/index.ex` — `/foods/:slug` (core nutrition sync; compounds +
  "Recipes with this food" behind `connected?/1` split in `load_species_sidecars/2`)
- `recipe_browser_live/index.ex` — `/browse`, owns `build_recipe_jsonld/1`
- `meal_plan_live/show.ex` + `meal_plan_live/index.ex` — `/meal-plans` (synchronous, no split)
- `public_nutritionist_live/*` — `/nutritionists` (synchronous in `mount`)
- `blueprint_live/show.ex` — `/blueprints/:slug` (synchronous)

## Method

### Phase 0 — Triage scorecard (breadth-first, NO fixes)

Score every public + consumer high-level LiveView on a fixed rubric; the ranked result
decides deep-dive order. Per view, read `mount`/`handle_params`/`handle_event` + template,
rate 🔴/🟡/🟢 per dimension:

| Dimension | Signal |
|---|---|
| Runtime perf | DB in `mount` not behind `connected?`, N+1, oversized `assigns`, no `stream`/`temporary_assigns` on big lists |
| Code health | god-module size, View/Update separation, direct `Repo.` in web layer |
| Parity | calc duplicated from a context that `/api/v1` also calls |
| Payload | heavy static diffs, data that should be lazy |
| SEO (public only) | core content + links in dead render? `connected?/1` split present where async used? |

### Phases 1…N — Deep dives (depth-first, one view per unit, ranked order)

Per view: confirm finding → fix → run SEO gate if public → keep docs in sync (CLAUDE.md
rule) → `mix test` for that surface → verify behavior unchanged. Each view = its own commit
on a feature branch, reviewable in isolation.

## Starting signals (gathered 2026-10-28)

**God-modules (lines):** `nutritionist_live/client_detail.ex` 1,444 · `calendar_live/calendar/widget.ex` 1,305 ·
`landing_live.ex` 1,265 · `meal_blueprint_live/index.ex` 1,014 · `professional_live/health_conditions.ex` 958 ·
`recipe_browser_live/index.ex` 946 · `meal_plan_live/show.ex` 922 · `professional_live/ai_bot_live/recipe_review.ex` 900 ·
`create_recipe_live/index.ex` 895 · `profile_live/index.ex` 884.

**Direct `Repo.` in web layer (smell → push to context):** `calendar_live/index.ex`,
`landing_live.ex`, `professional_live/ai_bot_live/config.ex`,
`professional_live/ingredient_live/ingredients_edit.ex`,
`professional_live/ingredient_live/show.ex`.

**DB work in `mount`:** `nutritionist_live/dashboard.ex`, `foods_live/index.ex`,
`nutritionist_live/user_invitations.ex`, `privacy_policy_live.ex`,
`create_recipe_live/index.ex`, `nutritionist_live/client_calendar.ex`,
`nutritionist_live/my_research_notes.ex`, `nutritionist_live/client_detail.ex`,
`nutritionist_live/articles.ex`, `landing_live.ex`.

**Already partially optimized:** `calendar_live/*` has a documented perf history
(week-scoped loading `list_calendar_user_meals/3` + denormalized `ingredient_user_meals.nutrients`
— see `project_calendar_performance` memory); treat as partially done, verify not regress.

## Progress tracker

Legend: ⬜ not started · 🔄 in progress · ✅ done · ⏭ deferred

### Phase 0 — Triage ✅ (completed 2026-10-28)

- ✅ Scored public tier (`:default3`, `:maybe`)
- ✅ Scored consumer tier (`:default`)
- ✅ Ranked scorecard produced (below)

#### Systemic finding (cross-cutting)

**No `connected?/1` guard on `mount` in private (noindex) consumer LiveViews.**
`calendar`, `create_recipe`, `meal_blueprint`, `basket`, authed `profile` tabs run their full
DB-loading `mount` on BOTH the disconnected HTTP render and the connected WS mount. These are
`noindex` + WebSocket-driven, so the disconnected render is pure waste. Guard heavy loads behind
`connected?/1` → ~halves DB work per load. SEO-safe precisely because private (inverse of the
public-page rule). `calendar` fires ~10 queries × 2. **Biggest single perf win; do early.**

#### Scorecard

Severity scale (higher = more urgent): **3 = problem · 2 = watch · 1 = ok · – = n/a**

| View | Route | Lines | Perf | Code | Parity | Payload | SEO | Key issues |
|---|---|---|---|---|---|---|---|---|
| landing_live | `/welcome` (pub) | 1265 | 3 | 3 | 1 | 2 | 1 | ~6 queries incl. `ORDER BY RANDOM()` run on every (double) render; `Repo.` in web; huge; counts should be cached. Must stay sync (SEO) |
| calendar/index (+widget 1305) | `/calendar` (priv) | 844 | 3 | 3 | 2 | 2 | – | ~10 queries unguarded ×2; `Repo.` in web; widget god-module. Verify not regress ([[project_calendar_performance]]) |
| recipe_browser/index | `/browse`,`/search` (pub) | 946 | 2 | 3 | 2 | 2 | 1 | owns `build_recipe_jsonld/1`; `get_user_essentials`+`get_address_agent` every mount; size; JSON-LD macro parity to verify |
| recipe_details_component (LiveComponent, reused in browse/home/profile/calendar modal) | — (modal) | 715 | 2 | 3 | 2 | 2 | – | `update/3` re-fetches user profile + `ingredient_display_names` on every parent re-render (unguarded; async comments ARE guarded); mixed concerns (comments/social/graphic/replies/nutrition); nutrient display → verify shared macro path. Modal → not in dead render |
| profile/index | `/profile[/:id]` (pub/priv) | 884 | 2 | 3 | 1 | 2 | 2 | mixes profile+recipe-detail+friends; double `get_user_essentials` in `:show_recipe`; authed tabs need `connected?` guard |
| meal_blueprint/index (+editor 854) | `/blueprints`-mgmt (priv) | 1014 | 2 | 3 | 1 | 2 | – | god-modules; `load_plans`/`load_client_targets` unguarded |
| create_recipe/index | `/create_recipe` (priv) | 895 | 2 | 2 | 1 | 1 | – | mount unguarded (quota + profile + unit); size; dead Spoonacular assigns |
| meal_plan/show | `/meal-plans/:slug` (pub) | 922 | 1 | 2 | 1 | 1 | 1 | well-built, synchronous, SEO-correct; size only (mostly render) |
| public_nutritionist/show | `/nutritionists/:slug` (pub) | 589 | 2 | 1 | 1 | 1 | 1 | several list loads per mount (required sync for SEO); fine |
| shopping_basket/index | `/basket` (priv) | 436 | 2 | 2 | 1 | 1 | – | `list_measurement_units`+baskets unguarded; `connected?` candidate |
| foods/index | `/foods` (pub) | 233 | 2 | 1 | 1 | 1 | 1 | species list correctly sync; `list_linked_compounds`+map build (filter UI) could defer behind `connected?` |
| species_detail/index | `/foods/:slug` (pub) | 477 | 1 | 1 | 1 | 1 | 1 | already has `connected?/1` split for sidecars — reference impl |
| home/index | `/home` (pub/priv) | 326 | 1 | 1 | 1 | 1 | 1 | `connected?`+3 streams; good shape |
| messages/index | `/messages` (priv) | 124 | 1 | 1 | 1 | 1 | – | 4× `connected?`; well guarded |
| blueprint/show | `/blueprints/:slug` (pub) | 324 | 1 | 1 | 1 | 1 | 1 | synchronous, SEO-ready (per seo.md) |
| meal_plan/index | `/meal-plans` (pub) | 132 | 1 | 1 | 1 | 1 | 1 | synchronous crawl hub; fine |
| friends, upgrade, trial, feedback, my_ingredient, user_invitations, public_nutritionist/{index,article} | various | <250 | 1 | 1 | 1 | 1 | 1 | small forms/lists; no action |

> ⚠️ `food_detail_live/index.ex` is **dead code** (not routed; superseded by `species_detail`, per seo.md). Don't optimize — candidate for deletion in a cleanup.

### Phase 1…N — Deep dives (ranked)

| # | View / change | Dimensions | Status | Branch/commit | Notes |
|---|---|---|---|---|---|
| 1a | **Cache cross-user reference reads** (measurement units, categories, food-restriction types, linked compounds) | perf | ✅ | 2026-10-28 | `Mehungry.ReferenceCache` (new `:reference_cache`, 1h TTL, write-invalidated); wrapped the 4 reads; `ReferenceCache.clear/0` in DataCase+ConnCase setup for test isolation. 145 domain tests pass. **Pure win, no UX change** (replaces the over-broad "halve all DB" framing — see Decisions log) |
| 1b | **`connected?/1` deferral** on calendar + meal_blueprint (heaviest authed only) | perf | ✅ | 2026-10-28 | calendar: mount keeps cheap user/profile, defers meals/blueprints/saved/follows/quota/assignment/share-card to `load_calendar_data/1`; also guarded `reload_week_meals/1` so apply_action is cheap on the dead render. meal_blueprint: defers blueprints/plans/clients. Safe empty defaults; 37 LV tests pass (LiveViewTest exercises both disconnected + connected render). Scoped to these 2 per AskUserQuestion; NOT applied to lighter pages |
| 2 | landing_live | perf, code, payload | 🔄 | 2026-10-29 | ✅ moved raw Repo `ORDER BY RANDOM()` query → `Food.list_recipes_with_nutrients/1` (+facade); dropped `import Ecto.Query` from web. ✅ cached the whole hero/trust bundle (recipes+featured pro+3 counts) via `ReferenceCache.fetch(:landing_bundle)` — ~6 queries now run ≤1×/TTL instead of per (double) render; RANDOM cost neutralized by caching. Kept synchronous (SEO). page_title/description + `ResearchType.buckets` left out of cache (locale/pure). 3 landing tests pass. ⬜ render split (1.1k-line template) deferred — needs visual verification (see row 2r) |
| 2r | landing_live render split | code | ⏭ | 2026-10-29 | **Skipped** (user call): low reward (static marketing markup, not logic) vs high risk on the top SEO page with no visual verify. #2 considered done. |
| 3 | calendar/index + widget | perf, code | ✅ | 2026-10-29 | ✅ `Repo.preload(struct(UserMeal))` in `apply_action(:new)` → `History.blank_user_meal/0`; dropped unused `Repo`/`UserMeal` aliases. ✅ Parity check clean — widget's `summary_metrics` already uses shared `NutrientUtils.macro_summary/1` (no dup). ⏭ widget template-split skipped (same blind-markup reasoning as 2r; logic is cohesive/tested/parity-correct). Perf was done in #1b. 14 tests pass |
| 4 | recipe_browser/index | code, parity, perf | ✅ | 2026-10-29 | **Audited clean, no change.** Parity: `jsonld_nutrition/1` already reuses `NutrientUtils.macro_summary/1` (no fork). Per-mount loads: `get_user_essentials(nil)`→`{nil,[],[]}` (free for crawler), `get_address_agent` is pure in-memory (no DB) — only cost is 3 cheap queries for logged-in hard-refresh; deferring would flicker save/follow buttons, bad trade on a sync-required public page. Size: no blind template split |
| 5 | profile/index | code, perf, **correctness** | ✅ | 2026-10-29 | `apply_action(:show_recipe)` reran `get_user_essentials/1` AND reassigned `current_user_follows` as raw `%Follow{}` structs — but the shared follow hook compares against integer follow-ids (mount maps to ids), so the recipe-modal follow button was silently broken. Now reuses mount's id list + drops the redundant reload → fixes the bug + removes queries. Mixed-concern split skipped (blind-refactor risk). 16 tests pass |
| 5b | recipe_details_component | perf, parity | ✅ | 2026-10-29 | `update/3` re-ran a profile query + `ingredient_display_names` resolve on **every** parent re-render; extracted to `maybe_assign_display_names/4`, guarded once-per-`{recipe.id, user_id}` (mirrors existing `maybe_load_recipe_async/3`). Parity clean — nutrition delegates to shared `<.recipe_details>`, no forked macro math. 44 modal-exercising tests pass (home/profile/browse) |
| 6 | meal_blueprint/index + editor | code, perf | ⬜ | | break up god-modules |
| 7 | create_recipe/index | code, perf | ⬜ | | remove dead Spoonacular assigns; split |
| 8 | meal_plan/show | code | ⬜ | | size only; low urgency |
| – | foods/index, basket, public_nutritionist/show | perf | ⬜ | | minor; fold into #1 where applicable |

## Decisions / constraints log

- 2026-10-28: Public + consumer tiers first; nutritionist + admin tools deferred to a later sweep.
- 2026-10-28: All four optimization dimensions in scope simultaneously.
- 2026-10-28: SEO guardrail (above) is a hard gate — perf work must not convert synchronous
  rankable content to async on public pages without the `connected?/1` split.
- 2026-10-28: **Reframed item #1.** The "mount runs twice → halve all DB work" framing was wrong:
  the double-mount only happens on hard loads/refresh (in-app nav is a single connected mount),
  and deferring heavy loads behind `connected?/1` trades useful first-paint HTML for an empty
  skeleton on refresh — a UX cost, not a pure win. Split #1 into: **1a** cache cross-user
  reference reads (pure win, done) and **1b** `connected?/1` deferral limited to the 2 heaviest
  authed pages (calendar, meal_blueprint) where Supabase-pool relief justifies the refresh-flash.
  Decided via AskUserQuestion ("Both: cache + deferral").
