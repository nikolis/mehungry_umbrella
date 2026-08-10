# Build Prompt — Mehungry (M3Hungry) React Native App

This is a self-contained prompt for an AI coding agent (or engineer) to build a
**React Native** mobile app that reproduces the Mehungry consumer experience,
powered by the REST + Phoenix Channels API defined in
[`docs/mobile_api_spec.md`](./mobile_api_spec.md). It was written after a
mobile-viewport walkthrough of the live web app; screen descriptions below match
what that app actually renders.

> Use it by pasting the whole file as the task brief. Build against the API spec;
> where the spec and this prompt disagree on a field name, the API spec wins.

---

## 1. Product summary

M3Hungry ("Know what's on your plate") is a **food/recipe social platform with a
nutrition-science backbone**. Users browse a social recipe feed, save/create
recipes, plan meals on a weekly calendar (with an AI meal-planner), keep a
shopping list, and explore a foods/species database and health-condition dietary
guidance. Premium tiers unlock AI recipe generation and meal planning.

**Brand**: wordmark "M3HUNGRY" (the "3" and "HUNGRY" in warm **paprika orange**
`#E1590E`-ish on a near-black warm-charcoal background). Dark theme by default.
Warm, food-forward, high-contrast. Palette tokens from the web design system:
`ink` (charcoal), `paprika` (orange accent/CTAs), `basil` (green), `parchment`
(light text). Rounded cards, generous spacing, large food photography.

---

## 2. Tech stack

- **React Native** with **Expo** (managed workflow) + **TypeScript**.
- **Navigation**: `@react-navigation/native` — bottom tab navigator + native
  stack per tab; modal stack for recipe detail, meal add/edit, onboarding.
- **Data**: **TanStack Query** (React Query) for REST caching/pagination +
  optimistic updates (likes, follows, basket toggles).
- **Realtime**: `phoenix` JS client (`import { Socket } from "phoenix"`) for
  channels (§API spec 13).
- **Auth storage**: `expo-secure-store` for the bearer token.
- **Auth (OAuth)**: `expo-auth-session` for Google / Facebook / Instagram → send
  provider token to `POST /api/v1/auth/oauth/:provider`.
- **Forms**: `react-hook-form` + `zod`.
- **Images**: `expo-image` (caching), `expo-image-picker` for recipe/avatar
  upload → presigned S3 PUT (§API spec 11).
- **Payments**: open Stripe Checkout/portal URLs via `expo-web-browser` (no
  native IAP in MVP).
- **State that isn't server data**: lightweight (Zustand or context) — theme,
  onboarding progress, current-week cursor.
- **i18n**: `i18n-js` or `react-intl` — English + Greek (Ελληνικά), driven by the
  user's `language_preference`.

Project layout: `src/{api,components,screens,navigation,hooks,store,theme,i18n}`.
Centralize the API client (base URL, bearer header injection, 401 → logout) in
`src/api/client.ts`; one hook module per resource (`useFeed`, `useRecipe`,
`useMeals`, `useBasket`, …).

---

## 3. Information architecture (bottom tab bar)

The web app's mobile nav is an 8-item bottom bar. For a native app, collapse to a
**5-tab bottom bar** with the rest reachable inside tabs (8 items is too many for
a thumb bar):

| Tab | Icon | Root screen | Contains |
|---|---|---|---|
| **Home** | logo/house | Recipe Feed | recipe detail (modal), comments |
| **Discover** | compass/book | Browse & Search | search, Foods (species), Conditions |
| **Create** | ⊕ (center, accent) | Create Recipe stepper | — |
| **Plan** | calendar | Weekly meal planner | day detail, add/edit meal, nutrition, basket |
| **Profile** | avatar | Profile | saved/created/ingredients tabs, settings, upgrade, notifications |

Keep **Foods** and **Conditions** as segmented sections inside **Discover** (the
web app gives them their own tabs; on mobile a segmented control at the top of
Discover — "Recipes · Foods · Conditions" — is cleaner). Shopping **Basket** is
reachable from **Plan** (header cart icon) and from a recipe's "add to list".

---

## 4. Screen-by-screen spec

Each screen lists: purpose, API calls, and key UI. All lists are infinite-scroll
using `meta.has_more`.

### 4.1 Onboarding wizard (modal, first launch / `onboarding_level < 3`)
A 3-step centered card over the app (the web app shows exactly this):
1. **Choose your language** — pill buttons `EN — English` / `ΕΛ — Ελληνικά`.
2. **What best describes your diet?** — single-select pills: Omnivore,
   Vegetarian, Vegan, Pescatarian (Omnivore preselected).
3. **Anything else?** — multi-select toggles, e.g. "I am lactose intolerant";
   plus condition opt-ins (Kidney Stones, IBS, …) if we surface them here.
- Progress bar (3 segments), **Next** button (paprika), **✕** to dismiss.
- API: `GET /preferences/options`, `PUT /me/preferences` (sets diet, intolerances,
  `onboarding_level`, `condition_opt_ins`). Re-openable from Profile.

### 4.2 Home — Recipe Feed (`GET /feed`)
Instagram-style vertical feed of recipe cards:
- Header: "Recipe Feed" / "Discover recipes from your community".
- Card: author row (avatar, name, "• 2d" relative time, "N recipes", **Follow**
  button), large 1:1 recipe photo, action row (❤ like with count, 💬 comment
  count, ↗ share), "N likes", author + description (truncated with "…"),
  hashtags (tappable → search by hashtag), "View all N comments".
- Tap photo/title → **Recipe detail** modal. Tap author → profile.
- Like/follow are optimistic (`POST/DELETE /recipes/:id/like`, `/users/:id/follow`).
- Live updates via `feed:lobby` channel (`recipe_created`, `recipe_liked`).
- Works logged-out (feed is 🔓); gate like/follow/save behind an auth prompt.

### 4.3 Recipe detail (modal, `GET /recipes/:id`)
- Hero image, save/bookmark toggle (top-right heart), title, description,
  hashtags.
- Meta chips: **⏱ 60 min total · Prep 20 · Cook 40 · 🍽 4 servings**.
- **Condition flags** banner when the user opted into a condition the recipe
  triggers (`condition_flags`: "Kidney Stones — avoid Oxalate (high)").
- **Ingredients** list (quantity + unit + name; tap ingredient → species page).
- **Steps** (numbered).
- **Nutrition** section from `nutrients` (energy/protein/… as a small table or
  chips; `primary_nutrients_size` marks the headline ones).
- Actions: **Add to shopping list** (`POST /basket/import/recipe/:id`),
  **Add to meal plan** (opens add-meal sheet prefilled with this recipe),
  like, comment.
- **Comments** section (`GET /recipes/:id/comments`, `POST …/comments`); live via
  `recipe:<id>` channel.

### 4.4 Create Recipe (stepper, `POST /recipes`)
Multi-step wizard (mirrors the web `/create_recipe` stepper):
1. Basics — title, description, cuisine, servings, difficulty, private toggle,
   prep/cook time.
2. Ingredients — searchable add (`GET /ingredients/search` USDA-backed), each row
   = ingredient + quantity + measurement unit + optional alias; add/remove rows.
3. Steps — ordered list of {title, description}, reorderable.
4. Photo — pick/crop image → presigned upload (§API spec 11) → `image_upload_id`.
5. Review & publish → `POST /recipes`.
- Edit mode reuses the flow (`PUT /recipes/:id`).

### 4.5 Discover — Browse / Search / Foods / Conditions
Segmented header: **Recipes · Foods · Conditions**.
- **Recipes**: search bar (`GET /search?q=`), results grid; hashtag & ingredient
  filters (`/search/hashtag/:h`, `/search/ingredient/:i` equivalents via query).
- **Foods** (`GET /species`): title "Foods & Nutrition", subtitle "Browse food
  species for nutrition facts, the research behind them, and the bioactive
  compounds they carry." Search box ("Search species — e.g. apple, spinach…"),
  "Showing N species", rows: **name** + family/variety tag, chevron.
  - **Species detail** (`GET /species/:slug`): nutrition facts, **bioactive
    compounds** with evidence (mean/range + evidence score), related conditions,
    ingredients.
- **Conditions** (`GET /conditions`): title "Health Conditions", subtitle
  "Dietary guidance by condition — which bioactive compounds to be mindful of,
  and the foods that contain them." Rows: **name** + category tag (renal,
  gastrointestinal, immune, Endocrine, Digestive…), chevron.
  - **Condition detail** (`GET /conditions/:id`): guidance, compound
    recommendations (avoid/limit/encourage + severity + evidence level), and the
    foods/species to be mindful of → tap a food → `/conditions/:id/species/:sid`.

### 4.6 Plan — Weekly meal planner (`GET /meals?start&end`)
- Header: week label with ‹ › date navigation ("Monday, 10 Aug"), a **+** button
  (paprika) to add a meal, a **⚡ Plan with AI** button, and a cart icon → Basket.
- Body: 7 day rows (Mon–Sun) with date; each expandable/tappable → **Day detail**.
- **Day detail**: meals grouped by meal type in fixed order — Breakfast, Morning
  Snack, Lunch, Afternoon Snack, Dinner, then **Unsorted** (`meal_type: null`)
  last. Each meal shows its recipes/ingredients and a small nutrition summary;
  swipe to delete, tap to edit; per-recipe **consume** toggle
  (`POST /meals/:id/consume`).
- **Add / edit meal** sheet: pick date, pick meal type (segmented incl.
  "Unsorted"), add recipes (search your saved/created + feed) and/or raw
  ingredients with qty+unit. `POST /meals` / `PUT /meals/:id`. Title is optional
  (server derives from meal type).
- **Nutrition details** for a day (`GET /meals/day/:date/nutrition`) vs. the
  user's `daily_calorie_target` — a ring/bar chart.
- **Plan with AI** (`POST /meals/plan-with-ai`): sheet to choose start date,
  #days, meals per day, optional notes → `202` job → subscribe to
  `meal_plan:<user_id>` channel; show progress, then refresh calendar on
  `result`. **Quota-gated**: if `403 {upgrade:true}`, route to Upgrade.

### 4.7 Basket — Shopping list (`GET /basket`)
- Title "Shopping Lists" / "Manage your grocery lists and track items".
- "N items · Last updated <when>"; empty state = cart illustration + "No items in
  this list".
- Item row: name, quantity + unit, checkbox = `in_storage` toggle
  (`PUT /basket/items/:id`), swipe to delete.
- Add item: manual (name + qty + unit, optional USDA search) or "import from
  recipe/meal" (`POST /basket/import/*`).

### 4.8 Profile (`GET /me`, `GET /me/recipes`)
- Header: avatar, email/alias, stats row — **Posted recipes · Followers ·
  Following**.
- Language toggle (EN / ΕΛ → `PUT /me/language`).
- **Upgrade to M3Hungry Plus** button → Upgrade screen (hide if already premium).
- Sub-tabs (segmented): **Saved · Created · My Ingredients · Friends' Ingredients
  · Edit Profile · Connected Accounts** (`GET /me/recipes?tab=…`,
  `GET /me/ingredients`, `PUT /me/profile`, `GET/DELETE /me/connected_accounts`).
- **Notifications / Invitations** entry (`user:<id>` channel + invitations API) —
  badge for pending nutritionist invitations; accept/decline.
- Settings row: Logout (`DELETE /auth/logout`), Delete Account.
- Public profile of another user = same header + their recipe grid
  (`GET /users/:id`, `/users/:id/recipes`).

### 4.9 Upgrade / Subscriptions (`GET /subscription`)
- Three plan cards: **Free** (0 AI recipes / 0 meal plans), **M3Hungry Plus**
  (€9.99/mo — 15 recipe generations, 4 meal plans), **Pro** (nutritionist tier —
  30 / 10). Show feature bullets and the user's current tier.
- "Upgrade" → `POST /subscription/checkout` → open Stripe URL in in-app browser;
  on return, refetch `/me` + `/subscription` (webhook activates tier server-side).
- Manage/cancel → `POST /subscription/portal`.

### 4.10 Auth screens
- **Login**: email + password, "Forgot your password?" (web view), **Log in**,
  OR divider, **Sign in with Facebook / Google**, "New here? Register with email".
- **Register**: email, password, alias → `POST /auth/register`; then a "confirm
  your email" notice (confirmation flow via web view for MVP).
- Persist token in secure store; auto-login on launch; 401 anywhere → clear token
  → Login.

---

## 5. Realtime (Phoenix Channels)

Connect `new Socket("wss://<host>/socket", { params: { token } })` after login.
Join:
- `feed:lobby` — prepend/patch feed cards on `recipe_created` / `recipe_liked`.
- `recipe:<id>` — while a recipe detail is open: live `comment_created`,
  `like_changed`.
- `user:<user_id>` — global notification listener → in-app toasts + Notifications
  badge (`invitation`, `follow`, `comment`, `ai_ready`).
- `meal_plan:<user_id>` — while an AI plan is generating → progress + `result`.

Disconnect on logout. Reconnect with backoff; rejoin channels on reconnect.

---

## 6. UX / visual requirements

- **Dark, warm-charcoal** background; **paprika** accents for primary CTAs,
  selected pills, the wordmark's active bits; **basil** green for positive/health
  states; muted parchment text with a lighter secondary tone for subtitles.
- Pill/segmented controls throughout (diet picker, meal types, profile sub-tabs).
- Recipe imagery is the hero — large, rounded, `expo-image` with blurhash/skeleton
  placeholders.
- Empty states with a centered icon + short copy (see Basket).
- A persistent small **Feedback** affordance (the web app has a floating
  "Feedback" chip) → simple feedback POST or mailto for MVP.
- Accessibility: min 44pt touch targets, dynamic type, VoiceOver labels on icon
  buttons (like/comment/share), sufficient contrast on the dark theme.
- Optimistic UI for like/follow/save/basket-check with rollback on error.
- Handle logged-out browsing gracefully (feed, foods, conditions, recipe detail
  are public); prompt to sign in when a gated action is attempted.

---

## 7. Out of scope for MVP

- The `/professional/**` admin tooling (users, science pipeline, AI bot, USDA
  schema, analytics) — **do not build**.
- The **nutritionist portal** (`/nutritionist/**`) — plan as a *phase 2* separate
  app or role-gated area (see API spec §14).
- Native in-app purchases — use Stripe web checkout for now.
- Offline write support — read caching via React Query is enough for MVP.

---

## 8. Deliverables & acceptance

1. Expo RN + TypeScript project with the 5-tab IA in §3.
2. All screens in §4 wired to the API spec, with loading/empty/error states.
3. Auth (email + at least Google OAuth) with secure token storage and 401
   handling.
4. Channels wired for feed, recipe room, notifications, and AI meal-plan progress.
5. English + Greek localization driven by `language_preference`.
6. Optimistic engagement (like/follow/save/basket toggle).
7. A short `README` documenting env config (`API_BASE_URL`, OAuth client ids) and
   how to point at a local Phoenix server (`http://<lan-ip>:4000`).

**Acceptance walkthrough** (matches the reviewed web flows): register/login →
complete the 3-step onboarding → scroll the feed and like a recipe → open a
recipe, add it to the shopping list and to Tuesday's dinner → open the weekly
planner and run "Plan with AI" (or see the quota gate) → browse Foods, open a
species, see its compounds → open a Condition and its foods → open Profile,
switch language to Greek, view the Upgrade screen.
