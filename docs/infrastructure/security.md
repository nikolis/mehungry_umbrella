# Mehungry Security — Account-Abuse Defenses

This document records the anti-abuse defenses in the platform: what exists, why,
where the code lives, how to operate it, and what to harden next. Revisit this
before extending auth, registration, or quota logic.

Last updated: 2026-07-11 — initial version, written after scripted **Gmail-alias
account farming** was spotted in production (accounts like
`r.uz.uf.i.w.owog8.21@gmail.com`, `mo.mi.we.yu.pe19.7@gmail.com`).

---

## 1. The threat that prompted this

Gmail (and `googlemail.com`) ignore **every `.`** in the local part and
**everything after a `+`**, so all of these deliver to one inbox
`ruzufiwowog821@gmail.com`:

- `r.uz.uf.i.w.owog8.21@gmail.com`
- `ruzufiwowog821+anything@gmail.com`
- `ru.zuf.iwo.wog821@googlemail.com`

Before this work the app deduped emails only by exact, case-folded string (a
`citext` unique index). Every alias was therefore a distinct account, so one
person could script unlimited signups from a single mailbox — polluting the DB,
burning the shared paid Spoonacular API key, and (critically) setting up to farm
per-account free quota the moment the free tier is ever raised above `0`.

---

## 2. Defenses in place

### 2.1 Email canonicalization (the core fix)

- **`Mehungry.Accounts.User.canonical_email/1`** — normalizes an address so
  provider aliases collapse to one identity:
  - lowercased + trimmed
  - `gmail.com` / `googlemail.com` → strip all `.` from the local part, drop
    everything from the first `+`, normalize domain to `gmail.com`
  - any other domain → strip only the `+tag` suffix (dots preserved)
  - a string without a single `@` is returned lowercased, unchanged
- **Schema/DB** — `users.canonical_email` (`citext`) with a **unique index**
  (`users_canonical_email_index`). Migrations `20260711143640` (add column +
  backfill) and `20260711143641` (unique index).
- **Enforcement** — `User.validate_email/1` sets `canonical_email` and adds
  `unsafe_validate_unique` + `unique_constraint` on it, so all three intake
  changesets (`registration_changeset`, `registration_3rd_party_changeset`,
  `email_changeset`) reject an alias of an existing address.
- **Lookups** — `Accounts.get_user_by_canonical_email/1` is used by
  `find_or_create/1` (OAuth can't create alias dupes) and as a fallback in
  `get_user_by_email_and_password/2` (the real owner can log in with any alias of
  their own address). The raw `:email` is preserved exactly as typed for
  display/notifications; `canonical_email` is the dedupe key only.

### 2.2 Cleanup of pre-existing alias clusters

- **`Accounts.dedupe_alias_accounts/1`** — groups users by `canonical_email`,
  keeps the **oldest** account per inbox, deletes the rest via the cascading
  `Accounts.delete_user/1`. `dry_run: true` (default) reports without deleting;
  every deletion is logged (`[dedupe_alias_accounts] deleting user ...`).
- **`mix mehungry.dedupe_aliases`** — dry-run by default; `--execute` to delete.
  Use it to preview against a target DB.
- **Self-healing migration** — `20260711143641` runs
  `dedupe_alias_accounts(dry_run: false)` **before** creating the unique index,
  so the automated migrator deploy cannot fail on dupes that already exist in
  production.

### 2.3 Registration rate limiting

- **`Mehungry.RateLimit.hit/3`** — fixed-window counters on the `:rate_limit`
  Cachex cache (started in `Mehungry.Application`). No external dependency. Fails
  **open** if the cache is unavailable (a cache hiccup never locks users out).
- **`MehungryWeb.Plugs.RegistrationThrottle`** — **5 signup POSTs / 10 min per
  IP** on `/register` and `/users/register` (pipeline `:registration_throttle`).
  Keys on the first `x-forwarded-for` hop, falling back to `conn.remote_ip`.

### 2.4 CAPTCHA on signup

- **`MehungryWeb.Turnstile`** — server-side Cloudflare Turnstile verification.
  The widget is on the registration form; `UserRegistrationController.create/2`
  verifies the token before creating the account.
- Config: `TURNSTILE_SITE_KEY` (public) / `TURNSTILE_SECRET_KEY` (verification),
  wired in `runtime.exs`. **When the secret key is unset (dev/test),
  verification is skipped** so local signups still work.

### 2.5 Email confirmation enforced at the authorization layer

- `MehungryWeb.UserAuth.require_authenticated_user/2` and the `UserAuthLive`
  `on_mount` now require `confirmed_at` (previously only the password-login form
  checked it). Password signups must click the emailed link; OAuth signups are
  auto-confirmed, so they are unaffected.
- Test note: `MehungryWeb.ConnCase.log_in_user/2` confirms the user first, since
  a logged-in test user now represents a confirmed, active account.

### 2.6 Gated the Spoonacular endpoint

- The `spoonacular_search` / `spoonacular_select` handlers in
  `create_recipe_live/index.ex` hit a **shared paid API key**. They are now
  rate-limited via `RateLimit.hit/3` at **20 requests / min per user** (search +
  import share one bucket).

---

## 3. Where quota abuse lives (context)

- Tiers/quota: `Mehungry.Subscriptions` — `free = 0/0`, `m3hungry_plus = 15/4`,
  `pro = 30/10` (recipe generations / meal plans per month). Owner email bypasses.
- Usage is tracked **per `user_id`, reset each calendar month** (`ai_usage`).
  This is the reason multi-accounting matters: **if the free tier is ever raised
  above `0`, alias/multi-account farming becomes directly valuable** — revisit
  §5 before making that change.
- Paid premium is granted **only** via a completed Stripe checkout webhook
  (`Billing.StripeHandler` → `Subscriptions.activate_pro`). No signup bonus, no
  referral/credit system, no free trial on account creation — so aliases cannot
  obtain paid quota for free today.

---

## 4. Operating notes

- **Deploy checklist:** set the Turnstile env vars; optionally run
  `mix mehungry.dedupe_aliases` against production first to preview removals;
  deploy — the migration auto-purges alias clusters then adds the unique index.
- **Verify real client IP** reaches the app: the throttle keys on
  `x-forwarded-for`. Behind the ALB, confirm the header is forwarded (otherwise
  every request looks like the load balancer's IP and the throttle is global).
- **Admin visibility:** `/professional/users`
  (`professional_live/users.ex`, admin-gated) lists users + tiers and supports
  delete. It does **not yet** cluster by canonical inbox (see §5).

---

## 5. Known gaps / what to harden next

Ordered roughly by value:

1. **Admin alias-cluster view** — extend `/professional/users` to group accounts
   by `canonical_email` so alias abuse is visible at a glance (data already
   exists; nothing surfaces it).
2. **Quota accounting beyond `user_id`** — before raising the free tier above
   `0`, move quota to inbox/IP/device-cluster level, or aliases reintroduce the
   incentive that canonicalization currently neutralizes.
3. **Disposable / throwaway-domain blocklist** — canonicalization stops Gmail
   aliasing, not `@mailinator.com`-style throwaways. Consider a deny-list of
   disposable domains at registration.
4. **Rate limits are per-instance** — `:rate_limit` is an in-memory Cachex cache,
   so limits are per node. On multi-node ECS the effective limit is `N × limit`.
   For strict global limits, back it with a shared store (e.g. Redis) or a
   dependency like `hammer`.
5. **OAuth email trust** — OAuth accounts are auto-confirmed. Google emails are
   provider-verified, but the Facebook fallback fabricates `#{uid}@facebook.user`
   when no email is returned — those never round-trip an inbox.
6. **No alerting** — abuse is only visible on the dashboard / in logs (consistent
   with the deliberate no-external-services stance; see `docs/observability.md`).
   A `[SlowRequest]`/error-tracker-style signal for signup spikes could help.
7. **Password policy** — min length 12; the uppercase/digit/punctuation rules are
   commented out in `User.validate_password/2`. Re-enable if desired.

---

## 6. File index

| Concern | File |
|---|---|
| Canonicalization + changeset | `apps/mehungry/lib/mehungry/accounts/user.ex` |
| Lookups + dedupe | `apps/mehungry/lib/mehungry/accounts.ex` |
| Dedupe CLI | `apps/mehungry/lib/mix/tasks/dedupe_aliases.ex` |
| Migrations | `apps/mehungry/priv/repo/migrations/20260711143640_*`, `..._143641_*` |
| Rate limiter | `apps/mehungry/lib/mehungry/rate_limit.ex` (cache in `application.ex`) |
| Registration throttle | `apps/mehungry_web/lib/mehungry_web/plugs/registration_throttle.ex` |
| CAPTCHA | `apps/mehungry_web/lib/mehungry_web/turnstile.ex`, `templates/user_registration/new.html.heex` |
| Registration controller | `apps/mehungry_web/lib/mehungry_web/controllers/user_registration_controller.ex` |
| Confirmation enforcement | `apps/mehungry_web/lib/mehungry_web/controllers/user_auth.ex`, `live/user_auth_live.ex` |
| Spoonacular gating | `apps/mehungry_web/lib/mehungry_web/live/create_recipe_live/index.ex` |
| Router wiring | `apps/mehungry_web/lib/mehungry_web/router.ex` (`:registration_throttle`) |
| Config | `config/runtime.exs` (`turnstile_*`) |
| Tests | `apps/mehungry/test/mehungry/accounts_test.exs` |
