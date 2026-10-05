# 02 — Product & Feature Inventory

*Read-only code trace. "Verified" = read in code; "Inferred" = deduced from structure, not traced end-to-end; data-population claims (how full a table is) are **not verifiable from code** and are flagged.*

## Feature inventory

| Feature (entry) | Intended user & problem | Status | User value / usability | Dependencies & data | Gaps / risks | Evidence |
|---|---|---|---|---|---|---|
| **Landing / marketing** (`/welcome`, `LandingLive`) | Visitor → conversion | Implemented | Polished, theme-aware, strong a11y (aria-labels, focus-visible); pulls a real DB recipe into the hero demo, labels AI output "example" | `AI.Bot.get_active_config_for_month`, `Food.Recipe.nutrients` | Hero blank if no recipe has non-empty `nutrients` (graceful fallback exists) | `landing_live.ex:18-55,228` |
| **Registration** (`/register`) | New user signup | Implemented | Turnstile CAPTCHA, re-renders on failure, email-confirmation gated | `Accounts.register_user`, Turnstile, `UserNotifier` | **No ToS/privacy consent checkbox**; email-send failure swallowed | `user_registration_controller.ex:20-66`; `templates/user_registration/new.html.heex` |
| **Login + confirmation gate** (`/login`) | Return user | Implemented | Unconfirmed users blocked, link auto-resent | — | — | `user_session_controller.ex:19-29` |
| **OAuth** (Facebook/Google/Instagram) | Social login | Implemented (inferred) | 3 providers | Ueberauth, `Accounts.OAuth` | Not traced end-to-end | `router.ex:119-126` |
| **Onboarding wizard** | First-run setup | Implemented | 3-step modal: diet+language → calorie target → condition badges; sets `onboarding_level:1` | `Accounts.update_user_profile`, `Food.diet_category_ids`, `Health.list_conditions_for_presentation` | Only 4 diet options + lactose flag; uses legacy palette (design inconsistency) | `onboarding/form_component.ex:286-331,197-206` |
| **Meal calendar** (`/calendar`) | Plan week, track nutrition | Implemented | Week/day views, portion adjust, per-day nutrition pie chart, basket import | `History.UserMeal`, `MealPlanGenerator`, Vega-Lite | Runs on `History.UserMeal`, **not** the `Plans` context (see tech-debt note) | `calendar_live/index.ex:235-349` |
| **AI weekly meal plan** (`ai_plan_week`) | Auto-fill the week | Implemented but **narrower than marketed** | Quota-gated, async | Assigns the user's **existing** recipes to days; does **not** generate new recipes; blueprint is an "inert hint until blueprint-aware planning lands" | Free tier = 0 → blocked on first try | `calendar_live/index.ex:272-287` |
| **AI recipe generation** (`/create_recipe`, `ai_generate`) | Generate a recipe | Implemented | Quota-gated; ingredient-provenance guard; maps to USDA | `Subscriptions`, `RecipeAgent`, USDA FDC (`FDC_API_KEY` required) | Needs Plus; Free = 0 | `create_recipe_live/index.ex:90-134` |
| **Manual recipe creation** (`/create_recipe`, `/stepper`) | Author recipes | Implemented | Multi-step; Spoonacular import assist | `Food.Recipes`, Spoonacular importer | — | `create_recipe_live/index.ex:137-184` |
| **Recipe browse/search** (`/browse`, `/search/*`) | Discover recipes | Implemented | By hashtag/ingredient/query | `Search`, `RecipeBrowserLive` | Not deep-traced | `router.ex:358-371` |
| **Social (feed, follow, vote, comment)** (`/home`, `/friends`) | Social engagement | Implemented | Follow, vote, comment | `Posts`, `Accounts.UserFollow` | Cold-start; no network effect yet | `router.ex:355`; `friends_live/index.ex` |
| **Shopping basket** (`/basket`) | Grocery list | Implemented | Import meal ingredients | `Inventory` | — | `router.ex:247-248` |
| **Foods / nutrition DB** (`/foods`, `SpeciesDetailLive`) | Explore foods, research | Implemented | Faceted filter by condition OR compound; paginated; localized | `Food.filter_species`, `Health.encouraged_*`, `SpeciesSearch` | Returns `[]` when both compound- and nutrient-engine miss → silent empty state | `foods_live/index.ex:225-240` |
| **Health conditions** (`/conditions`, `ConditionDetailLive`) | Condition-based food guidance | Implemented (**legal risk — see R1/R2**) | Lists guidance + implicated foods; carries "not medical advice" badge | `Health.list_conditions_for_presentation`, `species_for_condition` | Advice richness depends on data populated (**unverifiable**); can yield empty lists; **health-claims exposure** | `health_live/index.ex:7-20`; `condition_detail_live/index.ex:118-135` |
| **Meal blueprints** (`/blueprints/:slug`, `/nutritionist/blueprints`) | Reusable plan templates | Implemented | Public view + nutritionist editor; AI generate entries | `MealBlueprints`, `MealPlanGenerator` | — | `meal_blueprint_live/index.ex` |
| **Public nutritionist directory** (`/nutritionists`, `/nutritionists/:slug`) | Find a nutritionist | Implemented | SEO JSON-LD (LocalBusiness/Person), SSR for crawlers, articles/recipes | `Professionals.get_public_professional_by_slug` | Marketplace cold-start (empty directory = low trust) | `public_nutritionist_live/show.ex:202-232` |
| **Appointment booking** (booking modal) | Request a consult | Implemented — **free / request-only** | 3-step wizard (day→time→note); request→accept; `.ics` email | `Professionals.request_appointment`, `AppointmentMailerWorker` | **No payment step** — modal says "nothing is charged" | `public_nutritionist_live/show.ex:101-148,443` |
| **Stripe Connect payout onboarding** (`/nutritionist/profile`) | Nutritionist KYC for payouts | **Partial — onboarding only** | Express account + account link + status sync | `StripeHandler.create_connect_account/account_link/get_connect_account` | **Account created but never charged** — no PaymentIntent/fee/ledger anywhere | `profile_edit.ex:101-150`; `stripe_handler.ex:74-127` |
| **Subscription upgrade** (`/upgrade`) | Buy Plus/Pro | Implemented | Stripe Checkout, billing portal, GA purchase tracking, quota display | `StripeHandler.create_checkout_session`, `Subscriptions` | No 14-day withdrawal / VAT transparency (R9) | `upgrade_live/index.ex:67-164` |
| **Nutritionist dashboard / clients / records** (`/nutritionist/*`) | Manage practice | Implemented | Dashboard, clients, client calendar, records (CSV + manual), intake, consultation notes, articles | `Professionals.*`, `DietaryHistory` | **PII-heavy, special-category health data** (R3) | `router.ex:217-238` |
| **Scientific articles** (`/nutritionists/:slug/articles/:article_slug`) | SEO content | Implemented | Draft→publish, per-paragraph images/refs | `Professionals.Article*` | — | `router.ex:232-233,381-385` |
| **Profile** (`/profile`, `/profile/edit`) | Identity + prefs | Implemented | Diet/calorie/condition editing; design-system target | `ProfileLive`, `UserProfile` | — | `router.ex:360-363` |
| **Localization** (EN/EL) | Greek + English | Implemented | Locale-prefixed routes, Gettext | `Locale`, `SetLocale`, `RestoreLocale` | EL species list only shows translated species | `foods_live/index.ex:272-289` |
| **Account self-delete** (`/users/delete`) | GDPR erasure | Implemented — **incomplete + unsafe trigger** | Real cascade delete | `UserSessionController.delete_user` → `Accounts.delete_user` | Destructive **GET**; omits health-PII tables; misleading flash (R4) | `router.ex:435`; `accounts/admin.ex:137-217` |
| **Admin / professional back-office** (`/professional/*`) | Internal curation | Implemented (large) | Users, recipes, ingredients, science pipeline, AI bot, translations, analytics | many contexts | Admin-gated; out of consumer scope | `router.ex:128-204` |
| **Public REST API** (`/api/foundemental_foods`, `/api/parser/parse`) | External integration | Implemented | Token-guarded; OpenAPI docs at `/api/docs` | `RequirePublicApiToken` | — | `router.ex:76-93` |

## Critical user journeys (traced)

### (a) Register → confirm → onboard → first meal plan — *works, with one paywall friction*
Register (Turnstile → `register_user` → confirmation email, send-failure swallowed) → must click email link before login (`user_session_controller.ex:19`) → onboarding modal collects diet/language/calorie/conditions → first meal plan via `/calendar` "AI plan week" **hits `check_quota("meal_plan")` which is 0 on Free** (`calendar_live/index.ex:275-297`). **Friction:** the landing heavily markets "generate a full weekly meal plan", yet a new free user is blocked on the first attempt; and silent confirmation-email failures strand some users at login.

### (b) Browse/search → add to basket/calendar — *works (web layer)*
`/browse` or `/search/:query` → `RecipeBrowserLive` → detail → add. Calendar add routes through `History.UserMeal`; basket import via `/basket/import_items/:id`. Deep click path inferred from handlers.

### (c) Nutritionist profile → booking → **payment does not exist**
`/nutritionists/:slug` loads profile + 30-day availability → booking modal (day→time→note) → `request_appointment` (status `requested`) + `.ics` email → nutritionist accepts. **No payment anywhere on the mainline.** Grep for `PaymentIntent|application_fee|transfer_data|professional_payments` returns **zero hits** on master and the current branch (verified). Stripe Connect is payout-onboarding only (`stripe_handler.ex:74` "minimal onboarding slice"). **The paid-booking feature exists on an unmerged branch** (`new_professional_nutritionist_features`, commit `5d91fde5` — adds `professionals/appointment_payment.ex` + `application_fee` logic) **but has not been merged into master/current.** So `CLAUDE.md` and prior notes describing paid bookings / authorize-capture / 5% fee / `professional_payments` ledger describe *unmerged* work, not the deployed code.

### (d) Health condition → recommended foods — *path works, data-dependent, legally risky*
`/conditions` → `ConditionDetailLive` → foods via `Health.species_for_condition` and the USDA-nutrient engine (`foods_live/index.ex:225-240` OR-s a compound-fact engine and a nutrient-threshold engine). Per `CLAUDE.md`, compound-fact tables are largely empty, so results lean on the nutrient engine; some conditions can return an empty list with no explanation. **Actual data richness is unverifiable from code.** Legally this is the highest-risk surface (see [R1/R2](03-eu-compliance-risk-register.md)).

## Maturity & polish

**Production-grade:** landing page (strong a11y, honest "example output" labels), onboarding, upgrade/billing, registration/Turnstile/confirmation, booking wizard (real empty/success states, slot-race handling), the 676-LOC appointment calendar, analytics.

**Half-built / inconsistent:**
- **Stripe Connect payout onboarding with no charging path** — a dangling half-feature that implies a paid service which collects nothing.
- **AI weekly meal plan** assigns only *existing* recipes; blueprint is an inert hint — narrower than the "generate a full weekly meal plan" marketing.
- **`Plans` context appears orphaned** (`meal_plan.ex`, `daily_meal_plan.ex`, `meal.ex`) — referenced in the web layer only by `nutritionist_live/client_detail.ex`; consumer planning runs on `History.UserMeal`. Two parallel meal-plan models = tech-debt smell.
- **Health/science pipeline** is architecturally elaborate but data-sparse per `CLAUDE.md`.
- **Two palette systems coexist** (warm `ink/paprika/basil` tokens vs legacy `slate/primary-500`); design system rolled out to `/profile` only; three modal patterns coexist.

**Accessibility:** landing is exemplary; deeper views generally use semantic buttons + responsive classes. One concrete WCAG failure: `outline:none` on focusable elements in `head.html.heex:157-164` removes visible keyboard focus (WCAG 2.4.7). No automated a11y/contrast run was possible here.

## Data collected from users

| Surface | Data | Schema |
|---|---|---|
| Registration | email, hashed password, `canonical_email`, `confirmed_at` | `accounts/user.ex` |
| Profile | alias, intro, language, **daily_calorie_target, diet, lactose_intolerant**, onboarding level | `accounts/user_profile.ex:5-23` |
| Dietary rules | category/ingredient exclusions, **health-condition opt-ins** | `user_category_rule.ex`, `user_ingredient_rule.ex`, `user_condition_opt_in.ex` |
| Visit tracking | IP-based visits (x-forwarded-for) | `Meta`/`VisitorPlug`, `VisitLive` |
| Appointments | client id or external name, time, notes, meeting URL | `professionals/appointment.ex:9-22` |
| **Nutritionist client records (special-category health data)** | height, weight, BMI, BMR, TDEE, goal + free-form JSONB **medical history, medications, blood biochem, thyroid, gynecological history, allergies, alcohol/smoking/sleep, 24h recall** | `professionals/client_intake.ex:25-41` |
| Consultation notes / client file | nutritionist-owned patient file linked to a platform user | `professional_client.ex`, `consultation_note.ex` |
| Payments | Stripe customer/subscription ids; Connect account id | `Subscriptions`; `professional_profile.ex:34` |

## Marketing claims vs reality

| Landing claim | Reality | Verdict |
|---|---|---|
| "Track **168 nutrients** per meal" | Nutrition stored as `recipe.nutrients` JSONB, USDA-backed; "168" is hardcoded copy, not computed | **Plausible but unverified** — number is static copy |
| "**USDA FoodData Central**-backed" | `FoodData.Usda.*` clients present; AI maps ingredients to FDC | **Supported** |
| "**10,000+ foods**" | Hardcoded copy, not a live count | **Unverifiable from code** |
| "Generate **AI recipes**" | `RecipeAgent` wired, quota-gated (Plus; Free=0) | **Implemented** |
| "**Generate a full weekly meal plan in one request**" | Assigns *existing* library recipes; blueprint inert; Free=0 | **Partial / overstated** |
| "Nutrient **interactions** surfaced per recipe" | No per-recipe interaction surface found in traced code | **Unverified — honesty flag** |
| "Built for **nutritionists**" | Full `/nutritionist/*` suite exists | **Implemented** |
| Pricing Free/€9.99/€29.90 | Matches `UpgradeLive` + Subscriptions tiers | **Consistent** |
| "Payments processed securely by **Stripe** / cancel anytime" | True for subscriptions; **consultations are not charged at all** | **True for subs; implied paid marketplace collects nothing** |

**Takeaways:** biggest capability gap is the non-existent booking-payment flow; the AI meal plan is narrower than advertised; the "nutrient interactions per recipe" claim appears unsubstantiated; and static headline numbers ("168", "10,000+") can silently diverge from the real DB.
