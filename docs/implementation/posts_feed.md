# Posts, Feed & Engagement (`Mehungry.Posts`)

The community layer: the `Post` that backs every recipe, the home **feed**, and all
engagement — comments, threaded answers, and up/down votes on both posts and comments.
Backed by `Mehungry.Posts` and `MehungryWeb.HomeLive` (`/home`) +
`RecipeDetailsComponent`.

> The feed is **not the product** — `features/product_foundation.md` is explicit that the
> social graph is a channel, not the lead, and `features/normal_user.md` flags that a
> signed-in consumer currently lands here. This doc describes how it's built, not whether
> it should lead.

---

## The `Post` — one row per *surfaceable* thing

A `Post` (`posts`) is the feed-and-share envelope around a piece of content. It is **not**
limited to recipes; its `type_` discriminates what it carries:

| `type_` | Carries | Written by |
|---|---|---|
| recipe post (the common case) | `recipe_id` (+ `reference_id` for a re-share) | `create_post/_` on recipe create; one post **per recipe × language** |
| `"WEEKLY_PLAN"` | `published_meal_plan_id` + `weekly_plan_graphic_id` | `create_weekly_plan_post/_` (the calendar → share-card flow) |
| AI-bot social post | recipe, with social media targets | the AI-bot publish pipeline |

Scalar fields: `title`, `description` (may carry AI-appended `#hashtags`),
`language_name`, and three media URLs (`sm_`/`md_`/`bg_media_url`) + `reference_url`.
Associations: `belongs_to :user` / `:recipe` / `:reference` (re-shared recipe) /
`:weekly_plan_graphic` (`Food.WeeklyPlanGraphic`) / `:published_meal_plan`
(`PublishedPlans.PublishedMealPlan`); `has_many :comments` / `:upvotes` / `:downvotes`.

**Why a post exists per recipe × language:** the post is the localized, engageable
surface; a single recipe fans out to one post per translation so the feed can serve the
right language (`localize_for_language/_`, `create_post_for_translation/_`). This is the
reason `posts_total ≈ recipes × languages + bot posts` in `app_status.md` — posts are
**not** a count of user actions.

## Engagement model

| Concept | Schema (table) | Notes |
|---|---|---|
| Comment on a recipe/post | `Comment` (`comments`) | top-level |
| Reply to a comment | `CommentAnswer` (`comment_answers`) | one level deep |
| Vote on a post | `PostUpvote` / `PostDownvote` | the feed heart ↔ `like_recipe/unlike_recipe` |
| Vote on a comment / answer | `CommentVote` / `CommentAnswerVote` | threaded voting |

The context API is the full CRUD cross-product (`create_/update_/delete_/get_/list_/
change_` for each of `post`, `comment`, `comment_answer`, `comment_vote`,
`comment_answer_vote`, `post_upvote`, `post_downvote`), plus the ergonomic pairs the UI
actually calls: `upvote_post`/`downvote_post`, `vote_comment`,
`like_recipe`/`unlike_recipe`, and the read helpers `get_recipe_engagement/_`,
`preload_engagement/_`, `count_user_posts/_`, `count_user_comments/_`,
`post_exists_for?/_`.

### Notifications fire from the context, not the controller

**Emission lives inside `Posts.create_comment/_` and `create_comment_answer/_`** (they
call `Notifications.emit/3`), so **every** client — LiveView, REST, channel — produces a
notification from one place. This is the REST↔LiveView parity rule, and the reason it
moved down from the controllers (web comments used to emit nothing). See
[`notifications_system.md`](notifications_system.md) §3.

### Live updates

`subscribe_to_post/_`, `subscribe_to_post_comments/_`, `subscribe_to_recipe/_` back the
PubSub topics the feed/recipe-room LiveViews and the mobile `feed:lobby` / `recipe:<id>`
channels subscribe to (mobile spec §13).

## Media sync

`sync_recipe_post_media/_` keeps a recipe post's media URLs aligned with the recipe — and
is what lets the manual share flow swap in a generated **insight graphic** instead of the
plain cover (see [`ai/recipe_insight_graphics.md`](ai/recipe_insight_graphics.md)).

## Where it surfaces

- **Home feed** — `HomeLive` (`/home`): paginated `Post` stream (recipe cards + weekly-plan
  share cards), diet-mode filtered from the profile, infinite "load more". Vote/open/
  comment inline.
- **Recipe detail** — `RecipeDetailsComponent`: comments + answers + votes, live.
- **Mobile API** — `/api/v1/feed`, `/recipes/:id/comments`, the like/comment/vote
  endpoints (spec §4–§5). Controllers stay thin and delegate here.

## Related

- [`notifications_system.md`](notifications_system.md) — comment/reply/follow emission.
- [`published_plans.md`](published_plans.md) — the `WEEKLY_PLAN` post's payload.
- [`ai/recipe_insight_graphics.md`](ai/recipe_insight_graphics.md) — graphic swapped into a post's media.
- [`users/accounts.md`](users/accounts.md) — the follow graph the feed personalizes against.
