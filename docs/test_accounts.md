# Test accounts (third-party / bot testing)

Deterministic, **pre-confirmed** user accounts for exercising third-party and
bot integrations (OAuth callbacks, social publishing, API clients) against a
known, repeatable set of users. They bypass the email-confirmation flow so you
can log in immediately, and can be wiped back to a clean slate on demand.

## The accounts

Three fixed accounts, all sharing one password:

| Email | Name | Password |
|---|---|---|
| `bot1@mehungry.test` | Test Bot One | `TestBot-Passw0rd` |
| `bot2@mehungry.test` | Test Bot Two | `TestBot-Passw0rd` |
| `bot3@mehungry.test` | Test Bot Three | `TestBot-Passw0rd` |

The `.test` domain is reserved (RFC 2606), so these can never collide with a
real deliverable inbox. Each account is created with `confirmed_at` set, so no
confirmation email is needed.

Source of truth: `Mehungry.Accounts.TestAccounts`
(`apps/mehungry/lib/mehungry/accounts/test_accounts.ex`). Emails, names, and the
password are constants at the top of that module — edit them there if you need
different fixtures.

## Two ways to drive it

Both paths call the same `Mehungry.Accounts.TestAccounts` functions.

### 1. Mix task (script)

```bash
mix test_accounts          # status (also: mix test_accounts status)
mix test_accounts seed     # create any missing accounts (idempotent)
mix test_accounts reset    # delete all three, then recreate fresh
```

`Mix.Tasks.TestAccounts` — `apps/mehungry/lib/mix/tasks/test_accounts.ex`.

### 2. URL routes

```
GET /test-accounts          -> current status (JSON)
GET /test-accounts/seed     -> create any missing accounts
GET /test-accounts/reset    -> delete all three + recreate fresh
```

All three return JSON, e.g.:

```json
{
  "action": "reset",
  "password": "TestBot-Passw0rd",
  "accounts": [
    {"email": "bot1@mehungry.test", "name": "Test Bot One",
     "password": "TestBot-Passw0rd", "exists": true, "confirmed": true, "id": 49}
  ]
}
```

`MehungryWeb.TestAccountsController` —
`apps/mehungry_web/lib/mehungry_web/controllers/test_accounts_controller.ex`;
routes registered in `router.ex`.

## Behaviour

- **seed** — idempotent. Existing accounts are left in place (and re-confirmed
  if somehow unconfirmed); only missing ones are created.
- **reset** — deletes any of the three that exist via
  `Accounts.Admin.delete_user/1` (full leaf-first cascade of the user's recipes,
  comments, votes, follows, etc.), then recreates them fresh. Use this to clear
  state a bot run left behind and start over.

## Access gate

The routes create pre-confirmed accounts, so they are guarded (the Mix task is
not — it only runs where you already have shell access):

- **`:dev` / `:test`** — always open.
- **any other environment** (staging/prod) — the routes return **404** unless
  the `TEST_ACCOUNTS_TOKEN` env var is set **and** the request carries a
  matching `?token=` query param:

  ```
  GET /test-accounts/reset?token=<TEST_ACCOUNTS_TOKEN>
  ```

  Token comparison is constant-time (`Plug.Crypto.secure_compare/2`).
  Unauthorized requests get 404 (not 403) so the route's existence is not
  revealed. If `TEST_ACCOUNTS_TOKEN` is unset in prod, the routes are fully
  inaccessible.

Config wiring:
- `config/config.exs` — `config :mehungry_web, :test_accounts_env, config_env()`
  (compile-time env marker).
- `config/runtime.exs` — sets `:test_accounts_token` from `TEST_ACCOUNTS_TOKEN`
  when present.
