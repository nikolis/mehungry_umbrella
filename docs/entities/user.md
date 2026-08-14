# User

Table `users` · Schema `Mehungry.Accounts.User` (`lib/mehungry/accounts/user.ex`).
Index: [`entities.md`](entities.md). Context: [`../users/accounts.md`](../users/accounts.md).

The account entity — a human user or a **bot user** (AI-bot author with social tokens).

## Fields

| Field | Type | Notes |
|---|---|---|
| `email` | string | login identity |
| `canonical_email` | string | normalized for alias-dedupe — see [`../users/accounts.md`](../users/accounts.md) |
| `password` | string | **virtual, redacted** |
| `hashed_password` | string | redacted |
| `confirmed_at` | naive_datetime | email confirmation |
| `name`, `profile_pic` | string | display |
| `instagram_token`, `facebook_token`, `pinterest_token` | map | social tokens for bot users — see [`../ai/ai_bot.md`](../ai/ai_bot.md) |

## Relationships

- `has_one :user_profile` (UserProfile)
- `has_one :recipes` → [Recipe](recipe.md) *(author)*; owns private [Ingredient](ingredient.md)s (`user_id`)

## Referenced by

[`recipe.md`](recipe.md) · [`ingredient.md`](ingredient.md) · [`../users/accounts.md`](../users/accounts.md) · [`../ai/ai_bot.md`](../ai/ai_bot.md)
