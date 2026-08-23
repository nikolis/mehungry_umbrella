# Accounts — Overview

User identity, authentication, profiles, dietary rules, saved content, and
personalized grading. `Mehungry.Accounts` is a permanent **defdelegate facade** split
by concern into sub-modules; every public function stays callable through the facade,
and new code may call the sub-modules directly. (`Mehungry.Users` is a **deprecated**
facade over the same sub-modules — see below.)

The account entity itself is in the data dictionary: [User](../entities/user.md).

## What the context owns

| Sub-module | Owns |
|---|---|
| **`Accounts.Auth`** | Email/password auth — registration, session tokens, password change/reset, email change, email **confirmation** (all `UserToken`-based) |
| **`Accounts.OAuth`** | Ueberauth `find_or_create/1`, profile-pic sync, OAuth auto-confirmation, and provider **token storage** — DB (`update_user_tokens/2`) plus the `:cache_user_tokens` Cachex cache (`get_user_tokens/2`, `put_user_token/3`, keys pinned to `{Mehungry.Accounts, user_id}`) |
| **`Accounts.Profiles`** | User profile CRUD, `create_user_profile_if_needed/1` (both registration paths), language preference, follower/saved-recipe counts, `get_user_essentials/1`, opted-in health conditions |
| **`Accounts.Rules`** | User dietary rules — per-**category** and per-**ingredient** restriction rules |
| **`Accounts.Admin`** | `get_user!`, email/canonical-email lookups, filtered `list_users/1`, `count_users/0`, `delete_user/1` (explicit leaf-first cascade), `dedupe_alias_accounts/1` (Gmail-alias clusters, **dry-run by default**) |
| **`Accounts.UserContent`** | Saved recipes/posts, follows, created-recipe listings (folded from old `Mehungry.Users`) |
| **`Accounts.Grading`** | Personalized recipe scoring from category rules + follow graph (folded from old `Mehungry.Users`) |

## Dependencies & configuration

| Dependency | Used for | Key(s) |
|---|---|---|
| **Ueberauth — Facebook** | OAuth login + page tokens | `FACEBOOK_CLIENT_ID` / `FACEBOOK_CLIENT_SECRET` |
| **Ueberauth — Google** | OAuth login | `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` |
| **Ueberauth — Instagram** | OAuth login + IG tokens (bot users) | `INSTAGRAM_CLIENT_ID` / `INSTAGRAM_CLIENT_SECRET` |
| **Cloudflare Turnstile** | Registration CAPTCHA (skipped when the secret is unset) | `TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY` |
| **Admin gate** | Admin-only routes/dashboard | `config :mehungry, :admin_email` |
| **Cachex `:cache_user_tokens`** | Per-user provider-token cache, keys `{Mehungry.Accounts, user_id}` | — |

## Internal collaborators

| Context | What Accounts touches it for | Doc |
|---|---|---|
| **Food** | Saved/created [recipes](../entities/recipe.md); dietary rules over [categories](../entities/category.md)/[ingredients](../entities/ingredient.md); grading | [`../food/food.md`](../food/food.md) |
| **Posts** | Saved posts, follows | — |
| **Languages** | User language preference (FK by `name`) | [`../localization.md`](../localization.md) |
| **Professionals** | The Pro/nutritionist tier builds on user accounts | — |
| **AI Bot** | Bot users are `Accounts` users with social tokens (`register_3rd_party_user/1`) | [`../ai/ai_bot.md`](../ai/ai_bot.md) |
| **Web auth** | `UserAuth` plugs + `on_mount` inject session state into LiveViews | [`../infrastructure/architecture.md`](../infrastructure/architecture.md) |

## Where the code lives

- **Facade:** `apps/mehungry/lib/mehungry/accounts.ex` (+ deprecated `users.ex`).
- **Sub-modules:** `accounts/{auth,o_auth,profiles,rules,admin,user_content,grading}.ex`.
- **Schemas:** `accounts/{user,user_token,user_profile,user_category_rule,user_ingredient_rule,user_condition_opt_in,user_follow,user_post,user_recipe}.ex`.
- **Email:** `accounts/user_notifier.ex` — Swoosh confirmation / reset instructions.

## `Mehungry.Users` is deprecated

It was a second, overlapping user module. It is now a pure defdelegate facade over
`Accounts.UserContent` / `Accounts.Grading` (plus the canonical rule functions in
`Accounts` / `Food`). Existing call sites keep working; **new code should call the
Accounts modules directly.**

## Cross-cutting behaviors

1. **Email-alias abuse defense.** Signups are deduped on a normalized `canonical_email`
   (Gmail dots/`+tags` collapsed), rate-limited (`RateLimit`), Turnstile-gated, and
   **confirmation-enforced** — added after Gmail-alias signup farming.
   `Admin.dedupe_alias_accounts/1` cleans up existing clusters (dry-run by default). See
   [`../infrastructure/security.md`](../infrastructure/security.md).
2. **OAuth auto-confirms.** A user created (or matched) from a verified provider payload
   is auto-confirmed (`OAuth.maybe_confirm_user/1`) — the provider already verified the
   address; provider tokens land in the DB **and** the `:cache_user_tokens` cache.
3. **Deletion cascades.** `Admin.delete_user/1` removes a user's full data graph
   (explicit leaf-first cascade), not just the row.
4. **Facade stability.** Public functions never break when internals move — the same
   convention as `Mehungry.Food`. Add a `defdelegate` when adding a sub-module public fn.
5. **Bot users are normal users.** AI-bot authors are `Accounts` users carrying
   `instagram_token`/`facebook_token`/`pinterest_token` maps — see [`../ai/ai_bot.md`](../ai/ai_bot.md).

## Read next

- [`../entities/user.md`](../entities/user.md) — the User entity (schema, fields, relationships).
- [`../infrastructure/security.md`](../infrastructure/security.md) — auth hardening, alias defense, CAPTCHA.
- [`../subscriptions_billing.md`](../subscriptions_billing.md) — subscription tiers layered on accounts.
