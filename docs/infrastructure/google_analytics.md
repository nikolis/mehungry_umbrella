# Google Analytics (GA4)

## Config

`config/runtime.exs` sets `config :mehungry_web, ga_measurement_id: System.get_env("GA_MEASUREMENT_ID", "G-JPGJG6GCSK")`, read via `Application.get_env(:mehungry_web, :ga_measurement_id, "G-JPGJG6GCSK")` in `head.html.heex`. Override with the `GA_MEASUREMENT_ID` env var per-environment.

## Consent Mode v2

`gtag.js` loads on most pages (`head.html.heex`), but consent state gates what it's allowed to do with it:

```js
gtag('consent', 'default', { analytics_storage: '<granted|denied>' });
gtag('config', measurement_id, { send_page_view: false });
```

`analytics_storage` is derived from `@conn.assigns[:cookie_consent]` (set by `MehungryWeb.Plugs.CookieConsent`): `:accepted` → `granted`, `:declined`/`:pending` → `denied`. When denied, gtag automatically downgrades every hit to an anonymous **cookieless ping** — no `_ga`/`_gid` cookie, no persistent client ID — which still feeds GA4's aggregate/modeled reporting. This is Google's built-in mechanism for "basic signal pre-consent, full per-user tracking post-consent"; no app code branches on consent state beyond this one flag. `ConsentController.accept/decline` does a full-page redirect, so the next `head.html.heex` render picks up the new state automatically.

No `ad_storage`/`ad_user_data`/`ad_personalization` consent types are managed — this app has no ads/remarketing product attached.

### Suppression (localhost + team accounts)

`head.html.heex` computes a `ga_enabled` flag and omits the `gtag.js` script tags entirely when it's false, so no measurement hits are sent for that request. GA is suppressed when:

- the request host is `localhost` or `127.0.0.1` (local dev), **or**
- the signed-in `@conn.assigns[:current_user].email` is in the owner/team blocklist (`ga_blocked_emails` in `head.html.heex`).

Because every listener in `app.js` (`phx:page-loading-stop` page views, `phx:ga_event` custom events) guards on `typeof gtag === "function"`, omitting the script cleanly no-ops all tracking — no other wiring changes.

## SPA page views

This is a LiveView SPA — after the first full load, navigation happens via websocket patches, not new HTTP requests, so GA's automatic page_view (which only fires once, at script load) can't see in-app navigation on its own. Fix: `send_page_view: false` in the `gtag('config', ...)` call above, plus a manual `page_view` fired from a global listener in `assets/js/app.js` on the native LiveView lifecycle event `phx:page-loading-stop` (fires after every full load, `live_navigate`, and `live_patch`, once the URL/title have updated). This is the single source of all page_view events — do not re-enable `send_page_view` without removing this listener, or every navigation will double-count.

## Custom events

Two mechanisms, depending on whether the triggering code runs in a LiveView or a plain controller:

- **LiveView → `MehungryWeb.GoogleAnalytics.track(socket, event_name, params \\ %{})`** (`lib/mehungry_web/google_analytics.ex`) — wraps `push_event(socket, "ga_event", %{name: ..., params: ...})`. A generic listener in `app.js` (`phx:ga_event`) forwards these to `gtag('event', name, params)`. No consent check needed at either end — Consent Mode handles the pre-consent downgrade automatically.
- **Controller → one-shot flash.** `put_flash(:ga_event, Jason.encode!(%{name: ..., params: ...}))` before a redirect. `root.html.heex` reads `Phoenix.Flash.get(@conn.assigns.flash, :ga_event)` once (inside `<body>`, ahead of `{@inner_content}`) and emits an inline `gtag('event', ...)` call. Flash is consumed on read, so this can't double-fire on refresh/reconnect. Only used today for `sign_up` (`user_registration_controller.ex`); reusable as-is for future controller-driven events (email confirmation, login).

Module is named `GoogleAnalytics`, not `Analytics`, to avoid confusion with the unrelated in-house visit dashboard at `MehungryWeb.ProfessionalLive.AnalyticsLive` (built on `Mehungry.Meta` + Presence — a separate, first-party system with no relationship to GA).

## Event catalog

| Event | Trigger | File | Params |
|---|---|---|---|
| `page_view` | every full load / `live_navigate` / `live_patch` | `app.js` (`phx:page-loading-stop`) | `page_location`, `page_path`, `page_title` |
| `sign_up` | registration success | `user_registration_controller.ex` | `method: "email"` |
| `search` | non-empty recipe search | `recipe_browser_live/index.ex` | `search_term` |
| `create_recipe` | new recipe created (not edits) | `create_recipe_live/index.ex`, `save_recipe(socket, :index, ...)` | `recipe_id` |
| `begin_checkout` | subscribe/subscribe_nutritionist clicked, before Stripe redirect | `upgrade_live/index.ex` | `currency`, `value`, `items: [%{item_name: tier}]` |
| `purchase` | Stripe checkout returns `stripe_status=success` | `upgrade_live/index.ex`, `handle_params/3` | `currency`, `value`, `transaction_id`. Guarded against double-firing on refresh by `push_patch(to: "/upgrade")`, which strips the query params from the URL right after tracking. |

Lower-priority engagement events (post upvote/downvote, share, add-to-meal-plan, infinite scroll) are intentionally out of scope — add them the same way, via `MehungryWeb.GoogleAnalytics.track/3`, only in success branches.

## Adding a new event

From a LiveView: `socket |> MehungryWeb.GoogleAnalytics.track("event_name", %{key: value}) |> ...`. From a controller (pre-redirect, no LiveView involved): `put_flash(:ga_event, Jason.encode!(%{name: "event_name", params: %{key: value}}))`. Prefer [GA4's reserved event/param names](https://support.google.com/analytics/answer/9267735) (`search_term`, `transaction_id`, `currency`, `value`, `items`, etc.) where one exists, matching what `begin_checkout`/`purchase`/`search` already do.

## Verifying

Enable `gtag('set', 'debug_mode', true)` in devtools, drive the flow, and watch GA4 DebugView. Pre-consent, hits should appear as cookieless/modeled with no `_ga`/`_gid` cookie set (check the Application tab); after accepting, subsequent hits should carry a stable client ID. Confirm `page_view` count matches navigation count exactly (no dupes from `send_page_view` accidentally re-enabled, no misses from a broken `phx:page-loading-stop` listener).
