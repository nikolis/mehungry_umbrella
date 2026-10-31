# Published Meal Plans (`Mehungry.PublishedPlans`)

The **public, crawlable** meal-plan surface and the week-sharing flow. A user's live
calendar is private and `noindex`, so it can never rank; this context turns a *chosen
week* of that calendar into an immutable, SEO-indexed public snapshot served at
`/meal-plans/:slug`. Backed by `Mehungry.PublishedPlans`, `MealPlanLive`, and the
`profile?tab=meal_plans` tab.

> This is the SEO/sharing counterpart to the private calendar
> ([`history_calendar.md`](history_calendar.md)) — "the 7-day meal plan content people
> search for, with nutrition no recipe-blog listicle can match."

---

## The snapshot — `PublishedMealPlan`

One row per published week (`published_meal_plans`), an **immutable copy**, not a live
view of the calendar:

| Field | Meaning |
|---|---|
| `slug` (unique) | URL key (`slugify/1`), stable once published |
| `title`, `goal_label`, `summary_text` | display + short prose |
| `locale`, `week_start` | language + the Monday the snapshot covers |
| `days` (`{:array,:map}`) | day-by-day meals, each recipe linking to `/browse/:id` |
| `macros` (map) | truthful daily-average macros |
| `grocery` (`{:array,:string}`) + `grocery_groups` (`{:array,:map}`) | aggregated, aisle-grouped grocery list |
| `og_image_url` | the share card (Open Graph) |
| `recipe_count`, `visibility` (`"public"`), `published_at` | meta |
| `belongs_to :user` | author |

Because it's a frozen snapshot, editing the calendar afterward never changes a published
plan (re-publish to refresh).

## `publish_week/3` — self-contained by design

`publish_week(user, week_start, opts)` **re-derives the week from the DB** via
`History.list_calendar_user_meals/3` + `History.format_user_meals/1` — the caller passes
only `(user, week_start)`, no LiveView socket state. **Macro numbers come from
`Mehungry.NutrientUtils`, the same functions the calendar uses**, so the snapshot matches
the calendar to the gram (the REST↔LiveView parity rule applied to a second read surface;
see [`history_calendar.md`](history_calendar.md)). Grocery aisle grouping is
`GroceryAisle` + a `backfill_grocery_groups/0` for older rows.

## Context API

- **Publish/manage:** `publish_week/3`, `list_plans_for_user/_`, `count_plans_for_user/_`,
  `get_user_plan!/_`, `delete_plan/_`, `import_to_calendar/_` (lay a published plan back
  onto a calendar).
- **Public read:** `get_public_plan_by_slug/_` (+ `!`), `list_public_plans/_`,
  `list_public_plans_detailed/_`, `search_public_plans/_`.

## The share card + feed post

Publishing a week also produces a **deterministic SVG share card** and a `WEEKLY_PLAN`
`Post` (`Posts.create_weekly_plan_post/_`, linking `published_meal_plan_id` +
`weekly_plan_graphic_id`) so the week shows in the feed and renders a rich OG card when a
link is dropped in a social group. See [`posts_feed.md`](posts_feed.md) and memory
*Weekly-Plan Share Card + Post*.

## Surfaces

- **Public:** `/meal-plans` + `/meal-plans/:slug` (`MealPlanLive`) — synchronously
  rendered dead render for crawlers, with full nutrition + grocery list.
- **Profile:** the **Meal Plans** tab (`profile?tab=meal_plans`) lists a user's published
  plans (replaced the old Blueprints tab — memory *Profile Reorg*).
- **Sitemap:** published plans are SEO-indexed (unlike the private calendar).

## Not to be confused with

Four "plan"-shaped contexts coexist — see [`plans_vocabulary.md`](plans_vocabulary.md) for
the boundary. `PublishedPlans` is the **public snapshot of a calendar week**;
`MealBlueprints` is the reusable *targets template*; `History` is the live calendar;
`Plans` is the legacy meal-plan tree.

## Related

- [`history_calendar.md`](history_calendar.md) — the private calendar a week is snapshotted from.
- [`posts_feed.md`](posts_feed.md) — the `WEEKLY_PLAN` feed post.
- [`plans_vocabulary.md`](plans_vocabulary.md) — the four plan contexts disambiguated.
