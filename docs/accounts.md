# Accounts context

`Mehungry.Accounts` is a permanent defdelegate facade; the implementation
lives in sub-modules under `apps/mehungry/lib/mehungry/accounts/`:

| Module | Owns |
|---|---|
| `Accounts.Auth` | Email/password registration, session tokens, password change/reset, email change, email confirmation (all `UserToken`-based) |
| `Accounts.OAuth` | Ueberauth `find_or_create/1`, profile-pic sync, OAuth auto-confirmation, provider token storage (`update_user_tokens/2` in DB, `get_user_tokens/2` / `put_user_token/3` in the `:cache_user_tokens` Cachex cache, keys pinned to `{Mehungry.Accounts, user_id}`), `update_user/2` |
| `Accounts.Profiles` | User profile CRUD, `create_user_profile_if_needed/1` (called from both registration paths), language preference, follower/saved-recipe counts, `get_user_essentials/1` |
| `Accounts.Rules` | User category rules and ingredient rules (dietary restrictions) |
| `Accounts.Admin` | `get_user!`, email/canonical-email lookups, filtered `list_users/1`, `count_users/0`, `delete_user/1` (explicit leaf-first cascade), `dedupe_alias_accounts/1` (Gmail-alias clusters, dry-run by default) |
| `Accounts.UserContent` | Saved recipes/posts, follows, created-recipe listings (folded from the old `Mehungry.Users`) |
| `Accounts.Grading` | Personalized recipe scoring from category rules + follow graph (folded from the old `Mehungry.Users`) |

Schemas remain in `accounts/`: `User`, `UserToken`, `UserProfile`,
`UserRecipe`, `UserPost`, `UserFollow`, `UserCategoryRule`,
`UserIngredientRule`, plus `UserNotifier` (Swoosh emails).

## `Mehungry.Users` is deprecated

It was a second, overlapping user module. It is now a pure defdelegate facade
over `Accounts.UserContent` / `Accounts.Grading` (plus the canonical rule
functions in `Accounts` / `Food`). Existing call sites keep working; new code
should call the Accounts modules directly.

## Alias-abuse defense

`canonical_email` dedupe, `RateLimit`, Turnstile, and confirmation
enforcement — see the registration flow in `Accounts.Auth` and
`Admin.dedupe_alias_accounts/1`. OAuth logins auto-confirm pre-existing
unconfirmed accounts (`OAuth.maybe_confirm_user/1`) because the provider has
already verified the address.
