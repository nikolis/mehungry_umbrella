# Mehungry Mobile API Specification (REST + Channels)

Status: **proposed** — this document specifies the REST and Phoenix Channels API
to be **implemented in the current umbrella** (`apps/mehungry_web`) so that a
separate React Native client (see `docs/react_native_app_prompt.md`) can drive
the full consumer experience.

The web app today is server-rendered LiveView with session-cookie auth. Nothing
here replaces that — this is an **additive** JSON/WebSocket surface that reuses
the existing domain contexts (`Food`, `Accounts`, `Posts`, `History`,
`Inventory`, `Health`, `Survey`, `Subscriptions`, `Professionals`). Controllers
and channels should be thin: **delegate to the context modules**, never
re-implement business logic.

---

## 1. Conventions

- **Base URL**: `https://<host>/api/v1`
- **Format**: JSON only. Request and response bodies are `application/json`;
  `Accept: application/json`.
- **Auth**: `Authorization: Bearer <token>` (see §3). Endpoints marked
  🔓 are public (work with or without a token); 🔒 require a valid token.
- **IDs**: integer primary keys, serialized as JSON numbers, matching the
  current Ecto schemas.
- **Timestamps**: ISO-8601 UTC strings (`2026-08-10T14:30:00Z`). Naive
  datetimes (`start_dt`, `end_dt` on meals/baskets) are serialized as
  `2026-08-10T14:30:00` (no zone) since the domain stores them naive.
- **Money / plans**: tier strings are `"free" | "m3hungry_plus" | "pro"`.
- **Language**: honor `Accept-Language` or an explicit `?lang=en|el` param;
  default from `user_profile.language_preference` when authenticated, else `en`.

### 1.1 Envelope

Success (single): `{ "data": { ... } }`
Success (list): `{ "data": [ ... ], "meta": { "page": 1, "page_size": 20, "has_more": true } }`
Error: `{ "errors": { "detail": "message", "fields": { "field": ["msg"] } } }`

### 1.2 Standard status codes

`200` OK · `201` Created · `204` No Content · `400` bad request ·
`401` missing/invalid token · `403` authenticated but not allowed (e.g. quota,
private resource) · `404` not found · `422` changeset validation error
(fields map populated) · `429` rate-limited (registration, AI quota).

### 1.3 Pagination

Cursor-less page params for MVP: `?page=1&page_size=20`. The feed and browse are
infinite-scroll (the LiveViews already lazy-load "Loading more…"); `meta.has_more`
drives the client. A later cursor upgrade (`?before=<id>`) is noted per-endpoint.

---

## 2. Implementation map (where each endpoint lives)

| Area | New module (suggested) | Delegates to |
|---|---|---|
| Token auth | `Api.V1.SessionController`, `Api.Auth` plug | `Accounts.Auth` |
| Feed / recipes | `Api.V1.FeedController`, `RecipeController` | `Food.Recipes`, `Posts` |
| Social (like/comment/follow) | `Api.V1.EngagementController`, `FollowController` | `Posts`, `Accounts.Rules`/`UserContent` |
| Search | `Api.V1.SearchController` | `Search`, `Food.IngredientQueries` |
| Foods / species | `Api.V1.SpeciesController` | `Food` (`FoundementalFoodSpecies`), `Food.EvidenceAggregation` |
| Conditions | `Api.V1.ConditionController` | `Health` |
| Calendar / meals | `Api.V1.MealController` | `History` |
| Basket | `Api.V1.BasketController` | `Inventory` |
| Profile / preferences | `Api.V1.ProfileController`, `PreferencesController` | `Accounts.Profiles`, `Survey` |
| Subscriptions | `Api.V1.SubscriptionController` | `Subscriptions`, `Billing` |
| Notifications / invitations | `Api.V1.InvitationController` | `Professionals` |
| Nutritionist (phase 2) | `Api.V1.Nutritionist.*` | `Professionals`, `History` |

Add a new pipeline + scope in `router.ex`:

```elixir
pipeline :api_auth do
  plug :accepts, ["json"]
  plug MehungryWeb.Api.AuthPlug        # sets conn.assigns.current_user or 401
end

scope "/api/v1", MehungryWeb.Api.V1 do
  pipe_through :api                     # public
  post "/auth/login", SessionController, :create
  post "/auth/register", SessionController, :register
  post "/auth/oauth/:provider", SessionController, :oauth   # exchange provider token
  get  "/feed", FeedController, :index                       # 🔓 works logged-out
  get  "/recipes/:id", RecipeController, :show
  get  "/search", SearchController, :index
  get  "/species", SpeciesController, :index
  get  "/species/:slug", SpeciesController, :show
  get  "/conditions", ConditionController, :index
  get  "/conditions/:id", ConditionController, :show
end

scope "/api/v1", MehungryWeb.Api.V1 do
  pipe_through :api_auth                 # 🔒 token required
  delete "/auth/logout", SessionController, :delete
  get    "/me", ProfileController, :me
  # ... all authenticated resources below
end
```

---

## 3. Authentication

The app supports email/password and OAuth (Google, Facebook, Instagram). The
mobile client cannot use the browser cookie flow, so we mint **bearer tokens**
backed by the existing `users_tokens` table (reuse
`Accounts.Auth.generate_user_session_token/1`, exposed as an API-context token,
or a dedicated `:api` context token). Store the token in the OS keychain on the
device.

### `POST /api/v1/auth/register` 🔓
Rate-limited per IP (reuse `RegistrationThrottle` + Turnstile is web-only; for
mobile use an app-attestation/no-captcha path guarded server-side).
```json
// request
{ "email": "a@b.com", "password": "secret12", "alias": "Nikos" }
// 201
{ "data": { "token": "…", "user": { "id": 49, "email": "a@b.com" }, "requires_confirmation": true } }
```

### `POST /api/v1/auth/login` 🔓
```json
// request
{ "email": "bot1@mehungry.test", "password": "TestBot-Passw0rd" }
// 200
{ "data": { "token": "<opaque-bearer>", "user": { "id": 49, "email": "bot1@mehungry.test", "alias": "Test Bot One", "tier": "free", "onboarding_level": 0 } } }
// 401 on bad creds
```

### `POST /api/v1/auth/oauth/:provider` 🔓
`:provider` ∈ `google | facebook | instagram`. The mobile client performs the
native OAuth flow (e.g. `expo-auth-session`) and posts the provider's
`id_token`/`access_token`; the server verifies via Ueberauth/`Accounts.OAuth`,
upserts the user, and returns the same envelope as login.
```json
{ "provider_token": "ya29...", "provider": "google" }
```

### `DELETE /api/v1/auth/logout` 🔒
Revokes the presented token. `204`.

### `GET /api/v1/me` 🔒
Returns the current user + profile + tier + quota snapshot (drives Profile tab
and gating UI).
```json
{ "data": {
  "id": 49, "email": "bot1@mehungry.test", "alias": "Test Bot One",
  "avatar_url": null, "intro": null,
  "language_preference": "en", "daily_calorie_target": 2000,
  "onboarding_level": 3,
  "tier": "free",
  "quota": { "recipe_generations": {"used": 0, "limit": 0}, "meal_plans": {"used": 0, "limit": 0} },
  "counts": { "posted_recipes": 0, "followers": 0, "following": 0 },
  "condition_opt_ins": [ {"condition_id": 3, "name": "Kidney Stones"} ]
} }
```

Password reset / email confirmation reuse existing web routes for MVP (open in a
web view): `POST /users/reset_password`, `GET/POST /users/confirm`.

---

## 4. Feed & Recipes

### `GET /api/v1/feed` 🔓
The Home tab. Recipe cards from the community (`Food.Recipes.list_feed/…` +
`Posts`), newest first, infinite scroll. Logged-in requests personalize (follow
state, `condition_flags` for opted-in users).
```json
{ "data": [ {
  "id": 149,
  "title": "Sun-Roasted Eggplant & Chickpea Stew with Crumbled Feta",
  "description": "This soul-warming stew layers caramelized roasted eggplant…",
  "image_url": "https://…/recipe_images/149.jpg",
  "list_image_url": "https://…/recipe_images/149.jpg",
  "author": { "id": 33, "alias": "Nikos Galerakis", "avatar_url": "https://…", "recipe_count": 35 },
  "hashtags": ["vegetarian", "eggplant", "comfortfood"],
  "servings": 4,
  "prep_time": {"lower": 20, "upper": 20}, "cook_time": {"lower": 40, "upper": 40},
  "likes_count": 0, "comments_count": 0,
  "liked_by_me": false, "following_author": false,
  "inserted_at": "2026-07-10T09:00:00Z",
  "condition_flags": []
} ],
  "meta": { "page": 1, "page_size": 10, "has_more": true } }
```
Query: `?page`, `?page_size`, future `?before=<recipe_id>` cursor.

### `GET /api/v1/recipes/:id` 🔓
Full recipe detail (image, timing, servings, ingredients grouped, steps,
nutrients, hashtags, condition flags, engagement). Mirrors the recipe modal.
```json
{ "data": {
  "id": 149, "title": "…", "description": "…", "author": { … },
  "image_url": "…", "detail_image_url": "…",
  "servings": 4, "difficulty": 1, "cousine": "Mediterranean",
  "prep_time": {"lower":20,"upper":20}, "cook_time": {"lower":40,"upper":40},
  "private": false, "original_url": null,
  "hashtags": ["vegetarian"],
  "ingredients": [
    { "id": 8801, "quantity": 2.0, "ingredient_allias": "eggplant",
      "measurement_unit": { "id": 5, "name": "piece", "abbreviation": "pc" },
      "ingredient": { "id": 412, "name": "Eggplant", "species_slug": "eggplant" } }
  ],
  "steps": [ { "index": 1, "title": "Roast", "description": "Roast the eggplant…" } ],
  "nutrients": { "energy": {"amount": 168, "unit": "kcal"}, "protein": {"amount": 9, "unit": "g"} },
  "primary_nutrients_size": 4,
  "ingredient_interactions": [],
  "condition_flags": [ {"condition":"Kidney Stones","compound":"Oxalate","recommendation":"avoid","severity":"high"} ],
  "likes_count": 0, "comments_count": 0, "liked_by_me": false,
  "saved_by_me": false, "following_author": false
} }
```

### `POST /api/v1/recipes` 🔒
Create a recipe (the "+" / Create Recipe stepper). Multi-step in the UI but a
single create call server-side; images uploaded separately (§11).
```json
{ "title": "…", "description": "…", "servings": 4, "difficulty": 2,
  "cousine": "Mediterranean", "private": false,
  "preperation_time_lower_limit": 20, "cooking_time_lower_limit": 40,
  "hashtags": ["vegetarian"],
  "recipe_ingredients": [ {"ingredient_id": 412, "measurement_unit_id": 5, "quantity": 2.0, "ingredient_allias": "eggplant"} ],
  "steps": [ {"index": 1, "title": "Roast", "description": "…"} ],
  "image_upload_id": "s3-key-or-upload-token" }
```
`201` → full recipe. `PUT /api/v1/recipes/:id` (owner only), `DELETE …` (`204`).

---

## 5. Social engagement

### `POST /api/v1/recipes/:id/like` 🔒 → `{ "data": { "likes_count": 1, "liked_by_me": true } }`
### `DELETE /api/v1/recipes/:id/like` 🔒 → same shape, `liked_by_me: false`
(Backed by `Posts` up/downvote or a like assoc — reuse whatever the feed heart
currently toggles.)

### `GET /api/v1/recipes/:id/comments` 🔓
```json
{ "data": [ { "id": 7, "text": "Great!", "user": {"id":50,"alias":"Test Bot Two","avatar_url":null},
  "inserted_at": "…", "answers_count": 0, "votes_count": 2 } ] }
```
### `POST /api/v1/recipes/:id/comments` 🔒 `{ "text": "…" }` → `201`
### `POST /api/v1/comments/:id/answers` 🔒 `{ "text": "…" }`
### `POST /api/v1/comments/:id/vote` 🔒 `{ "value": 1 }` / `DELETE …`

### `POST /api/v1/users/:id/follow` 🔒 / `DELETE /api/v1/users/:id/follow` 🔒
`{ "data": { "following": true, "followers_count": 12 } }`

### `POST /api/v1/recipes/:id/save` 🔒 / `DELETE …` — the profile "saved" tab
(`Accounts.UserRecipe`).

---

## 6. Profiles

### `GET /api/v1/users/:id` 🔓 — public profile (avatar, alias, intro, counts).
### `GET /api/v1/users/:id/recipes` 🔓 `?type=created|saved` — grid for a profile.
### `GET /api/v1/me/recipes` 🔒 `?tab=saved|created|my_ingredients|friends_ingredients`
   — powers the Profile tab's sub-tabs seen in the web app.
### `PUT /api/v1/me/profile` 🔒 — edit profile
```json
{ "alias": "Nikos", "intro": "Home cook", "daily_calorie_target": 2200 }
```
### `GET /api/v1/me/connected_accounts` 🔒 / `DELETE /api/v1/me/connected_accounts/:provider`
   — the "connected accounts" profile sub-tab (OAuth link/unlink).
### `PUT /api/v1/me/language` 🔒 `{ "lang": "el" }` — mirrors `/users/language/:lang`.
### `GET /api/v1/me/ingredients` 🔒 / `POST` / `PUT /:id` / `DELETE /:id`
   — "my ingredients" (custom user ingredients from `/my_ingredients/*`).

---

## 7. Onboarding & dietary preferences (Survey)

Drives the 3-step onboarding wizard (language → diet → conditions/intolerances)
and the diet picker. Backed by `Survey` + `Accounts.Rules`/`UserConditionOptIn`.

### `GET /api/v1/preferences/options` 🔓
Static vocabulary for the wizard.
```json
{ "data": {
  "languages": [ {"code":"en","label":"EN — English"}, {"code":"el","label":"ΕΛ — Ελληνικά"} ],
  "diets": [ {"key":"omnivore","label":"Omnivore"}, {"key":"vegetarian","label":"Vegetarian"},
             {"key":"vegan","label":"Vegan"}, {"key":"pescatarian","label":"Pescatarian"} ],
  "intolerances": [ {"key":"lactose","label":"I am lactose intolerant"} ]
} }
```
### `GET /api/v1/me/preferences` 🔒 — current selections + `onboarding_level`.
### `PUT /api/v1/me/preferences` 🔒
```json
{ "language": "en", "diet": "omnivore", "intolerances": ["lactose"],
  "condition_opt_ins": [3], "onboarding_level": 3 }
```
Setting `condition_opt_ins` enables the per-recipe `condition_flags` (badges).

---

## 8. Foods (species) & Health conditions

### `GET /api/v1/species` 🔓 `?q=apple&page=`
Foods tab list. Each row: name, family/variety tag, slug.
```json
{ "data": [ {"id":1,"name":"Acerola","slug":"acerola","variety":"west indian cherry","family":null,"scientific_name":"Malpighia emarginata"},
             {"id":2,"name":"Agave","slug":"agave","family":"Asparagaceae"} ],
  "meta": { "total": 7 } }
```
### `GET /api/v1/species/:slug` 🔓
Species detail: description, nutrition facts, bioactive compounds (evidence
summaries via `Food.EvidenceAggregation`), related conditions, ingredients.
```json
{ "data": {
  "id": 12, "name": "Spinach", "slug": "spinach", "scientific_name": "Spinacia oleracea",
  "family": "Amaranthaceae", "variety": null,
  "compounds": [ { "name": "Oxalate", "mean": 750.0, "unit": "mg/100g",
    "range": [600,900], "variance": 12.3, "evidence_score": 0.82, "study_count": 5 } ],
  "related_conditions": [ {"id":3,"name":"Kidney Stones","recommendation":"avoid","severity":"high"} ],
  "ingredients": [ {"id":412,"name":"Spinach, raw"} ]
} }
```

### `GET /api/v1/conditions` 🔓
Conditions tab. `{ "data": [ {"id":3,"name":"Kidney Stones","category":"renal","slug":"kidney-stones"}, … ] }`

### `GET /api/v1/conditions/:id` 🔓
Condition detail: dietary guidance, implicated compounds, and the foods/species
to be mindful of (`Health.species_for_condition/2`).
```json
{ "data": {
  "id": 3, "name": "Kidney Stones", "category": "renal",
  "compound_recommendations": [ {"compound":"Oxalate","recommendation":"avoid","severity":"high","evidence_level":"moderate","source":"curated"} ],
  "species": [ {"id":12,"name":"Spinach","slug":"spinach","reason_compound":"Oxalate"} ]
} }
```
### `GET /api/v1/conditions/:id/species/:species_id` 🔓 — the drill-in "food for
condition" page (`/conditions/:id/food/:species_id`).

---

## 9. Calendar (meal planner)

Weekly planner. A day groups `UserMeal`s by `meal_type`
(`breakfast, morning_snack, lunch, afternoon_snack, dinner`, plus `null` =
Unsorted, shown last). Backed by `History` + `History.UserMeal`.

### `GET /api/v1/meals?start=2026-08-10&end=2026-08-16` 🔒
```json
{ "data": {
  "range": {"start":"2026-08-10","end":"2026-08-16"},
  "days": [ {
    "date": "2026-08-10",
    "meals": [ {
      "id": 91, "title": "Lunch", "meal_type": "lunch",
      "start_dt": "2026-08-10T13:00:00", "end_dt": "2026-08-10T13:30:00",
      "recipes": [ {"recipe_id":149,"title":"…","servings":2,"image_url":"…","consumed":false} ],
      "ingredients": [ {"ingredient_id":412,"name":"Eggplant","quantity":1.0,"measurement_unit":{"id":5,"name":"piece"}} ],
      "nutrition_summary": {"energy":336,"protein":18}
    } ]
  } ],
  "meal_type_vocabulary": [ {"key":"breakfast","label":"Breakfast"}, {"key":"morning_snack","label":"Morning Snack"},
    {"key":"lunch","label":"Lunch"}, {"key":"afternoon_snack","label":"Afternoon Snack"},
    {"key":"dinner","label":"Dinner"}, {"key":null,"label":"Unsorted"} ]
} }
```

### `GET /api/v1/meals/day/:date` 🔒 — single day (day drill-in).
### `POST /api/v1/meals` 🔒 — add a meal (the "+" and `/calendar/:start/:title`).
```json
{ "date": "2026-08-12", "meal_type": "dinner", "title": null,
  "recipe_user_meals": [ {"recipe_id": 149, "servings": 2} ],
  "ingredient_user_meals": [ {"ingredient_id": 412, "measurement_unit_id": 5, "quantity": 1.0} ] }
```
`meal_type: null` or `"unsorted"` → Unsorted bucket. `title` optional (server
derives from meal_type). `201` → the created meal.
### `PUT /api/v1/meals/:id` 🔒 — edit (also used to move between days/types).
### `DELETE /api/v1/meals/:id` 🔒 → `204`.
### `POST /api/v1/meals/:id/consume` 🔒 — mark a recipe consumed
   (`ConsumeRecipeUserMeal`), feeding nutrition history.
### `GET /api/v1/meals/day/:date/nutrition` 🔒 — daily nutrition details
   (the `/calendar/details/:date` view) vs. `daily_calorie_target`.

### `POST /api/v1/meals/plan-with-ai` 🔒 🎯 quota-gated
The "Plan with AI" button. Delegates to `AI.MealPlanGenerator` /
`MealPlanAgent`. Enforce `Subscriptions.check_quota(user, :meal_plan)`; on
exhaustion return `403` with an upgrade hint. Because generation is slow, this
returns `202 Accepted` with a job id and the client subscribes to the
`meal_plan:<user_id>` channel (§13) for progress + result, OR polls
`GET /api/v1/meals/plan-with-ai/:job_id`.
```json
// request
{ "start": "2026-08-11", "days": 5, "meals_per_day": ["breakfast","lunch","dinner"], "notes": "high protein" }
// 202
{ "data": { "job_id": "…", "status": "queued" } }
// 403 when out of quota
{ "errors": { "detail": "Meal plan quota reached for m3hungry_plus tier", "upgrade": true } }
```

---

## 10. Shopping basket

One active basket per user with items (from recipes or manual). Backed by
`Inventory`.

### `GET /api/v1/basket` 🔒
```json
{ "data": {
  "id": 4, "title": "Groceries", "updated_at": "2026-08-10T…",
  "items": [ { "id": 55, "name": "Eggplant", "quantity": 2.0, "in_storage": false,
    "measurement_unit": {"id":5,"name":"piece"}, "recipe_id": 149,
    "usda_fdc_id": 169228, "nutrition_data": {"energy":50} } ],
  "items_count": 1 } }
```
### `POST /api/v1/basket/items` 🔒 `{ "name":"Eggplant","quantity":2.0,"measurement_unit_id":5,"usda_fdc_id":169228 }`
### `PUT /api/v1/basket/items/:id` 🔒 — edit qty / toggle `in_storage` (checkbox).
### `DELETE /api/v1/basket/items/:id` 🔒 → `204`.
### `POST /api/v1/basket/import/recipe/:recipe_id` 🔒 — add all a recipe's
   ingredients (mirrors `/basket/import_items/:id`). Body: `{ "servings": 4 }`.
### `POST /api/v1/basket/import/meal/:meal_id` 🔒 — add a planned meal's items.
### `GET /api/v1/ingredients/search?q=onion` 🔒 — USDA-backed ingredient search
   for adding items / recipe ingredients (`FoodData.Usda.SearchClient` via
   `FDC_API_KEY`).

---

## 11. Media upload

Recipe / avatar images go to S3 (existing `Mehungry.S3`). Two supported flows:

- **Presigned PUT** (preferred): `POST /api/v1/uploads/presign`
  `{ "kind": "recipe_image", "content_type": "image/jpeg" }` →
  `{ "data": { "upload_id": "recipe_images/tmp/uuid.jpg", "url": "<presigned>", "headers": {…} } }`.
  Client PUTs the binary to `url`, then passes `upload_id` in the create/update body.
- **Direct multipart** (fallback): `POST /api/v1/uploads` `multipart/form-data`
  → `{ "data": { "upload_id": "…", "url": "https://…" } }`.

---

## 12. Subscriptions & upgrade

The Upgrade screen and profile gating. Backed by `Subscriptions` + `Billing`.

### `GET /api/v1/subscription` 🔒
```json
{ "data": {
  "tier": "free",
  "plans": [
    { "key":"free","name":"Free","price":null,"features":["…"],"recipe_generations":0,"meal_plans":0 },
    { "key":"m3hungry_plus","name":"M3Hungry Plus","price":{"monthly":"€9.99"},"recipe_generations":15,"meal_plans":4 },
    { "key":"pro","name":"Pro","price":{"monthly":"…"},"recipe_generations":30,"meal_plans":10 } ],
  "quota": { "recipe_generations": {"used":0,"limit":0}, "meal_plans": {"used":0,"limit":0} }
} }
```
### `POST /api/v1/subscription/checkout` 🔒
`{ "plan": "m3hungry_plus", "interval": "monthly" }` →
`{ "data": { "checkout_url": "https://checkout.stripe.com/…" } }`.
The mobile client opens the Stripe URL in a web view / in-app browser; the
existing `POST /webhooks/stripe` webhook activates the tier. (Native IAP is a
later consideration — out of scope for MVP.)
### `POST /api/v1/subscription/portal` 🔒 → Stripe billing portal URL (manage/cancel).

---

## 13. Phoenix Channels (real-time)

Reuse the existing `MehungryWeb.UserSocket` (currently a no-op scaffold). Add
**token auth on connect** and the channels below. Client connects to
`wss://<host>/socket` with `params: { token: "<bearer>" }`.

```elixir
# user_socket.ex
def connect(%{"token" => token}, socket, _info) do
  case MehungryWeb.Api.Auth.verify(token) do
    {:ok, user} -> {:ok, assign(socket, :user_id, user.id)}
    _ -> :error
  end
end
def id(socket), do: "user_socket:#{socket.assigns.user_id}"
```

### `feed:lobby` 🔓/🔒 — live feed
- **Join**: optional; server pushes when new recipes are published or an author
  the user follows posts.
- **Push → client**: `"recipe_created"` `{ recipe: <feed card> }`,
  `"recipe_liked"` `{ recipe_id, likes_count }`.
- Backed by broadcasting from `Posts`/`Food.Recipes` on publish (the AI bot
  pipeline and user posts).

### `recipe:<id>` 🔓 — live comments/likes on an open recipe
- **Push → client**: `"comment_created"` `{ comment }`, `"like_changed"`
  `{ likes_count, liked_by_user_ids? }`.
- **Client → server**: `"new_comment"` `{ text }` (also available over REST §5;
  the channel is for live rooms). Reply with the created comment; server
  broadcasts to the topic.

### `user:<user_id>` 🔒 — personal notifications
- Authorization: topic user_id must equal `socket.assigns.user_id`.
- **Push → client**: `"notification"` `{ type, payload }` for:
  - nutritionist **invitation received** (`type: "invitation"`) — badge on the
    Notifications screen (`/notifications/invitations`),
  - **new follower** (`type: "follow"`),
  - **comment on your recipe** (`type: "comment"`),
  - **meal plan / recipe generation ready** (`type: "ai_ready"`).

### `meal_plan:<user_id>` 🔒 — AI meal-plan generation progress
- **Push → client**: `"progress"` `{ job_id, status: "generating"|"done"|"error", pct }`,
  `"result"` `{ job_id, meals: [ … ] }` (same shape as §9 day meals). Client
  refreshes the calendar on `result`. Mirrors the "Plan with AI" async flow.

### `presence` (optional, phase 2)
The web app uses `MehungryWeb.Presence` for active-user tracking/visits. Expose
via `Phoenix.Presence` on `user:*` if the mobile app needs online indicators;
not required for MVP.

---

## 14. Nutritionist portal (phase 2)

The `/nutritionist/**` LiveViews (dashboard, clients, client calendar,
appointments, invitations) are a **separate professional persona**. Recommend a
**separate RN app or a role-gated section** rather than bloating the consumer
MVP. When built, mirror §9 for the client calendar and add:

- `GET /api/v1/nutritionist/clients`, `GET /api/v1/nutritionist/clients/:id`
- `GET/POST/PUT/DELETE /api/v1/nutritionist/clients/:id/meals*` (same meal shapes
  as §9, scoped to the client — reuse `NutritionistLive.ClientCalendar` logic in
  `Professionals` + `History`)
- `GET /api/v1/nutritionist/appointments`
- `GET/POST /api/v1/nutritionist/invitations`, and the client-side
  `GET/POST /api/v1/me/invitations` (accept/decline) for the consumer app's
  Notifications screen.

Gate all of these with `Subscriptions.nutritionist?/1` / `pro?/1`.

Admin/`/professional/**` tooling is **explicitly out of scope** for mobile.

---

## 15. Cross-cutting requirements

- **Quota enforcement**: every AI endpoint (`meals/plan-with-ai`, recipe
  generation if exposed) must call `Subscriptions.check_quota/2` before work and
  `record_usage/2` after; owner email bypass already exists. Return `403 {upgrade:true}`.
- **Authorization**: private recipes, other users' baskets/meals → `403`/`404`.
  Reuse existing context-level scoping (always filter by `current_user.id`).
- **Rate limiting**: reuse `MehungryWeb.RateLimit` for auth + AI endpoints.
- **Versioning**: everything under `/api/v1`; additive changes only within v1.
- **Serialization**: use dedicated JSON views/`Jason.Encoder`-free view modules
  (`*JSON`) per resource; do **not** encode Ecto structs directly (avoids
  leaking internal fields and association placeholders).
- **Testing**: `ConnCase` request tests per controller; `ChannelCase` for each
  channel. Keep the `meal_type` vocabulary test coupling in mind (§9 must stay in
  sync with `History.MealType.values/0`).
- **Telemetry**: the existing telemetry/error tracking wraps the endpoint, so API
  requests appear in `/dashboard` automatically.

---

## 16. Endpoint index (quick reference)

```
POST   /api/v1/auth/register
POST   /api/v1/auth/login
POST   /api/v1/auth/oauth/:provider
DELETE /api/v1/auth/logout
GET    /api/v1/me
GET    /api/v1/feed
GET    /api/v1/recipes/:id
POST   /api/v1/recipes
PUT    /api/v1/recipes/:id
DELETE /api/v1/recipes/:id
POST   /api/v1/recipes/:id/like        DELETE /api/v1/recipes/:id/like
POST   /api/v1/recipes/:id/save        DELETE /api/v1/recipes/:id/save
GET    /api/v1/recipes/:id/comments    POST /api/v1/recipes/:id/comments
POST   /api/v1/comments/:id/answers    POST /api/v1/comments/:id/vote
POST   /api/v1/users/:id/follow        DELETE /api/v1/users/:id/follow
GET    /api/v1/users/:id               GET /api/v1/users/:id/recipes
GET    /api/v1/me/recipes
PUT    /api/v1/me/profile
PUT    /api/v1/me/language
GET    /api/v1/me/connected_accounts   DELETE /api/v1/me/connected_accounts/:provider
GET/POST/PUT/DELETE /api/v1/me/ingredients
GET    /api/v1/preferences/options
GET/PUT /api/v1/me/preferences
GET    /api/v1/search
GET    /api/v1/ingredients/search
GET    /api/v1/species                 GET /api/v1/species/:slug
GET    /api/v1/conditions              GET /api/v1/conditions/:id
GET    /api/v1/conditions/:id/species/:species_id
GET    /api/v1/meals                   GET /api/v1/meals/day/:date
POST   /api/v1/meals                   PUT/DELETE /api/v1/meals/:id
POST   /api/v1/meals/:id/consume
GET    /api/v1/meals/day/:date/nutrition
POST   /api/v1/meals/plan-with-ai      GET /api/v1/meals/plan-with-ai/:job_id
GET    /api/v1/basket
POST/PUT/DELETE /api/v1/basket/items[/:id]
POST   /api/v1/basket/import/recipe/:recipe_id
POST   /api/v1/basket/import/meal/:meal_id
POST   /api/v1/uploads/presign         POST /api/v1/uploads
GET    /api/v1/subscription
POST   /api/v1/subscription/checkout   POST /api/v1/subscription/portal

CHANNELS (wss://host/socket, params: {token})
  feed:lobby        recipe:<id>        user:<user_id>
  meal_plan:<user_id>
```
