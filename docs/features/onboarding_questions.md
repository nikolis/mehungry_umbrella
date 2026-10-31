# Onboarding Questions (database-driven, admin/nutritionist-editable)

Both onboarding questionnaires in the app are stored in the database and editable
through the UI — no code change is needed to add, edit, reorder, or retire a
question. One generic engine (`Mehungry.Onboarding`) serves two surfaces.

## 1. Normal-user onboarding questions

- The first-run wizard (`MehungryWeb.Onboarding.FormComponent`) keeps its fixed
  **essentials** step (diet / language / lactose / daily-calorie target — these
  drive food-category filter rules and locale, so they stay typed on
  `Accounts.UserProfile`).
- **Admins** add extra questions in `/professional/onboarding-questions/user`.
  Each is either a **value** input (free text or number) or a **multiple-choice**
  question (pick-one / pick-many) whose choices the admin edits. Prompts and
  choice labels are authored in **English and Greek**.
- When any `user`-scope questions exist, the wizard appends a final step rendering
  them; the answers are saved as `Onboarding.Answer` rows against the user
  (`subject_type: "user"`). With no admin questions the wizard is unchanged.
- **The nutritionist sees these answers** on the client's file
  (`MehungryWeb.NutritionistLive.ClientDetail` → "Onboarding answers" panel),
  because a client's `ProfessionalClient.user_id` is the same platform user.

## 2. Nutritionist client onboarding questionnaire

- **Admins** curate a default template in
  `/professional/onboarding-questions/client-default`. It is seeded from the
  legacy `Professionals.DietaryHistory.Fields` list (see `seed_defaults/0`), and
  is **separate** from the user-onboarding set above.
- **Each nutritionist controls their own set** at
  `/nutritionist/onboarding-questions`. The first time they open it, the admin
  default is **snapshotted** into questions they fully own (add / edit / delete /
  reorder). Later admin edits to the template do **not** disturb an existing
  nutritionist's copy (`ensure_client_questions/1`).
- **The client self-fills** the questionnaire at
  `/:locale/nutritionist-onboarding/:professional_id` (only reachable by that
  nutritionist's linked clients — a link appears on the client's
  `/notifications/invitations` page). Answers are stored against the
  `ProfessionalClient` (`subject_type: "professional_client"`).
- This is **additive** to the nutritionist's clinical `ClientIntake`
  (anthropometrics / energy); it does not change energy calc or the CSV importer.

## Data & code

- Context: `Mehungry.Onboarding` (`apps/mehungry/lib/mehungry/onboarding.ex`).
- Schemas: `Onboarding.Question` (+ embedded `QuestionOption`) and
  `Onboarding.Answer` — see `docs/implementation/entities/onboarding.md`.
- Scopes: `"user"`, `"client_default"` (both admin-owned, `professional_id` nil),
  `"client"` (per-nutritionist, `professional_id` set).
- Answers are rows keyed on `(question_id, subject_type, subject_id)` (upsert
  target); `prompt_snapshot` keeps an answer readable if its question is deleted.
- Admin + nutritionist editors share `MehungryWeb.OnboardingQuestionLive.{Shared,
  FormComponent}`; choices are edited with the repo's `sort_param`/`drop_param`
  add/remove convention.

## Out of scope (v1)

- Not exposed over the mobile `/api/v1` yet (the wizard essentials still are via
  `preferences_controller`). Extend the mobile spec in the same change if added.
- The nutritionist's clinical `ClientIntake`/`Fields` questionnaire is **not** yet
  migrated onto this engine — the two coexist.
