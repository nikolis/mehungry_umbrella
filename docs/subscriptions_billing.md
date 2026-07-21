# Subscriptions & billing

## Architecture

- `Mehungry.Subscriptions` (`apps/mehungry/lib/mehungry/subscriptions.ex`) owns tier state. Backing schema is `Subscriptions.UserSubscription` (table `user_subscriptions`, one row per user, unique on `user_id`). `get_subscription/1` returns an **unpersisted** `%UserSubscription{tier: "free", status: "active"}` when no row exists — never `nil`.
- Tiers: `"free"` (0/0), `"m3hungry_plus"` (15 recipe / 4 meal-plan generations per month), `"pro"` (30/10) — limits in `@monthly_limits` in `subscriptions.ex`. Owner email (`nikolisgal@gmail.com`) bypasses all quota checks (`owner?/1`).
- `Mehungry.Billing.StripeHandler` (`apps/mehungry/lib/mehungry/billing/stripe_handler.ex`) does everything Stripe-API-facing: `create_checkout_session/6`, `create_billing_portal_session/2`, and `handle_webhook/2`.
- Webhook ingress: `POST /webhooks/stripe` → `MehungryWeb.StripeWebhookController` → `StripeHandler.handle_webhook/2`. Route defined with its own `:stripe_webhook` pipeline (`router.ex`); raw body is preserved for signature verification by `MehungryWeb.Plugs.CacheRawBody`.
- `/upgrade` (`MehungryWeb.UpgradeLive.Index`, page title "Manage subscriptions"; the sidebar nav link is also labeled "Manage subscriptions" — the route/module name still says "upgrade" but the page also serves existing subscribers managing their plan) builds Stripe Checkout sessions with `metadata: {user_id, tier}` baked into both the session and `subscription_data.metadata`. The landing page and profile page CTAs linking to `/upgrade` still read "Upgrade to Mehungry Plus", aimed at free users who haven't subscribed yet.
- **`pro` users cannot subscribe to `m3hungry_plus`.** `pro` (30/10) is a strict superset of `m3hungry_plus` (15/4), so re-subscribing would just add a second, redundant charge. `UpgradeLive.Index`'s `"subscribe"` event handler checks `socket.assigns.subscription.tier == "pro"` and shows a flash error instead of calling `StripeHandler.create_checkout_session/6`; the Mehungry Plus card in `index.html.heex` shows "Included in your Pro plan" instead of subscribe buttons for those users. This is a UI/LiveView-layer guard only — `StripeHandler.create_checkout_session/6` itself has no tier-conflict check, so anything that calls it directly (future admin tooling, scripts) bypasses this rule.

**Webhooks are load-bearing, not best-effort.** `Subscriptions.activate_pro/4` and `activate_nutritionist/4` — the only functions that write `tier` into the DB — are called from exactly one place: `StripeHandler.dispatch_event/1` on `checkout.session.completed`. There is no reconciliation job, no polling fallback, nothing else in the codebase calls them. If the webhook never arrives, the customer is charged and the app never learns about it. `customer.subscription.updated` / `.deleted` are equally load-bearing for keeping `status`/`period_end` in sync afterward (renewals, cancellations, past_due).

**Known race condition:** `dispatch_event` for `checkout.session.completed` makes a synchronous Stripe API call (`fetch_subscription_period_end/1`) before writing the DB row — this can take several seconds. The browser's redirect back to `success_url` typically arrives *before* that finishes, so `/upgrade` can render "Free" for a moment right after a successful purchase even though the payment succeeded. The success banner itself is driven purely by the `stripe_status=success` URL param, not by the fetched tier, so it will show even during that window. A page refresh a few seconds later shows the correct state.

## Local webhook testing with the Stripe CLI

Stripe CLI binary: not preinstalled in this environment. Standalone install (no root needed):

```bash
curl -sL https://github.com/stripe/stripe-cli/releases/latest/download/stripe_<version>_linux_x86_64.tar.gz -o /tmp/stripe-cli.tar.gz
tar -xzf /tmp/stripe-cli.tar.gz -C ~/.local/bin stripe
```
(`~/.local/bin` is already on `PATH` in this environment.) `apt install stripe` also works if you have sudo.

Step by step, including every gotcha hit while verifying this the first time:

1. **`stripe login`** — opens a browser pairing flow. **Verify it pairs to the correct Stripe account/sandbox.** A single Stripe login can have multiple sandboxes; `stripe config --list` shows a `[default]` block with `account_id` / `display_name`. That display name is also shown as the business name on Stripe's hosted Checkout page (top-left banner) once you start a real checkout. If the two don't match, you paired to the wrong account — re-run `stripe login` and pick the right one in the browser's account picker. This project's local test key belongs to a sandbox that shows as **"Glaucous Balance"** on Checkout.
2. **`stripe listen --forward-to localhost:4010/webhooks/stripe`** — start this before testing, leave it running.
3. **Edit `phxserver.sh`, not `.env`.** `phxserver.sh` hardcodes its own `export STRIPE_WEBHOOK_SECRET=...` line and does **not** source `.env` — editing `.env`'s copy has zero effect on the running server. Find the `STRIPE_WEBHOOK_SECRET` line in `phxserver.sh` and replace it with the secret from step 4.
4. **Pull the secret from the actual running listener**, not a separate call. Each `stripe listen` invocation can mint its own ephemeral signing secret — grab it from that specific session's own startup line (`Ready! ... Your webhook signing secret is whsec_...`), or from `stripe listen --print-secret` run as part of the same session. A secret fetched from an earlier/different `stripe listen` run will not match and every event will 400.
5. **Restart `mix phx.server`** — `STRIPE_WEBHOOK_SECRET` is read once at boot via `config/runtime.exs`; no live reload.
6. **Watch for a dead websocket.** The CLI's connection to Stripe can silently die mid-session (its log shows `Error on WriteJSON: ... i/o timeout`) without the process exiting. If you complete a checkout and see zero new `-->` lines in the listener's output, kill and restart `stripe listen` rather than assuming the app is broken.
7. **Drive a real checkout**, don't use `stripe trigger checkout.session.completed`. The trigger command can't reproduce the `user_id`/`tier` session metadata `StripeHandler` depends on, so `dispatch_event` will see `user_id: nil` and no-op. Go to `/upgrade`, click Subscribe, use card `4242 4242 4242 4242` with any future expiry/CVC.
8. **Verify in three places**, don't trust the immediately-rendered page (see race condition above):
   - `stripe listen` terminal: each event should show `200`, not `400`.
   - Server logs: `Activated m3hungry_plus for user <id>` / `Activated Pro (nutritionist) for user <id>` (from `stripe_handler.ex`).
   - DB directly — fastest ground truth: `Mehungry.Subscriptions.get_subscription(user_id)` via `iex -S mix` or a one-off `mix run -e`.

## Debugging checklist

| Symptom | Cause |
|---|---|
| Every event `400` in `stripe listen` | Webhook secret mismatch. Re-pull from the *currently running* listener session and check `phxserver.sh` (not `.env`) got updated, then restart the server. |
| Zero events reach the listener (no `-->` lines at all) | Account/sandbox mismatch — `stripe login` is paired to a different account than the one behind `STRIPE_SECRET_KEY`. Confirm with `stripe events list` / `stripe checkout sessions list` (empty despite a completed checkout = wrong account) and compare `stripe config --list`'s `display_name` to the name shown on the Checkout page banner. |
| Events stopped mid-session | Listener's websocket died silently; restart `stripe listen`. |
| `/upgrade` shows "Free" right after a successful test payment | Expected — see the known race condition above. Check the DB or refresh after a few seconds. |

## Creating disposable test users

Registration in this environment goes through Cloudflare Turnstile, which blocks headless/automated browsers. For webhook testing, create a confirmed user directly instead:

```bash
mix run -e '
email = "webhook_test@example.com"
{:ok, user} = Mehungry.Accounts.register_user(%{email: email, password: "SomeLongPassword123!"})
user |> Ecto.Changeset.change(confirmed_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)) |> Mehungry.Repo.update!()
IO.puts("USER_ID=#{user.id}")
'
```
