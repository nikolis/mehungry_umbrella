# Onboarding Question & Answer

Tables `onboarding_questions`, `onboarding_answers` · Context `Mehungry.Onboarding`
(`lib/mehungry/onboarding.ex`). Index: [`entities.md`](entities.md).

The database-driven onboarding questionnaires — admin-editable user-onboarding
questions and the nutritionist-controlled client questionnaire. Feature overview:
[`../../features/onboarding_questions.md`](../../features/onboarding_questions.md).

## Question (`onboarding_questions`)

Schema `Mehungry.Onboarding.Question` (`lib/mehungry/onboarding/question.ex`).

| Field | Type | Notes |
|---|---|---|
| `scope` | string | `"user"` · `"client_default"` · `"client"` |
| `professional_id` | id → `users` | nil for `user`/`client_default`; the owning nutritionist for `client` |
| `prompt_en` / `prompt_el` | string | per-locale prompt; `prompt/2` picks locale with EN fallback |
| `question_type` | string | `"value"` · `"single_choice"` · `"multi_choice"` |
| `value_kind` | string | `"text"` · `"number"` (value questions only) |
| `options` | embeds_many `QuestionOption` | `{key, label_en, label_el}`; `key` auto-slugged + preserved across edits |
| `required` | boolean | |
| `position` | integer | order within `(scope, professional_id)`; auto-assigned on create |
| `active` | boolean | inactive = hidden from the wizard/form |
| `source_key` | string | stable slug carried from template → nutritionist snapshot |

- **Scopes:** `user` (appended to the normal-user wizard), `client_default`
  (admin template), `client` (a nutritionist's own snapshot). `ensure_client_questions/1`
  copies the active `client_default` rows into `client` rows **once** (snapshot on
  first use), independent of later template edits.
- Choice options edited via the repo `sort_param: :options_sort` / `drop_param:
  :options_drop` add/remove convention; `validate_choice_options` requires ≥1 choice.

## Answer (`onboarding_answers`)

Schema `Mehungry.Onboarding.Answer` (`lib/mehungry/onboarding/answer.ex`).

| Field | Type | Notes |
|---|---|---|
| `question_id` | id → `onboarding_questions` | `on_delete: :delete_all` |
| `subject_type` | string | `"user"` (→ `users.id`) · `"professional_client"` (→ `professional_clients.id`) |
| `subject_id` | bigint | the user or client id (not a hard FK — polymorphic) |
| `value_text` | text | value-question answer |
| `selected_options` | array(string) | chosen option keys for choice questions |
| `prompt_snapshot` | string | denormalized prompt; keeps the answer readable if the question is deleted |

- **Unique** on `(question_id, subject_type, subject_id)` — the `upsert_answers/4`
  conflict target (one row per question per subject; re-submitting replaces).
- `answers_for_user/1` / `answers_for_client/1` return display-ready
  `{question, answer}` pairs ordered by question `position`.

## Referenced by

User-onboarding answers surface on [`user.md`](user.md)'s client file via
`MehungryWeb.NutritionistLive.ClientDetail`; the nutritionist questionnaire relates
to the professionals' `ProfessionalClient` file.
