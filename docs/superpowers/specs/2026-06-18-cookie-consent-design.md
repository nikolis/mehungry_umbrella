# Cookie Consent Banner — Design Spec

**Date:** 2026-06-18  
**Scope:** GDPR-compliant cookie consent for m3hungry.com  
**Compliance target:** GDPR (EU/EEA) — strict opt-in before analytics processing

---

## Cookie Inventory

### Strictly necessary (no consent required)

| Cookie | Key | Purpose | Lifetime |
|---|---|---|---|
| Session | `_mehungry_web_key` | Auth token, CSRF, LiveView socket ID | Browser session |
| Remember me | `_mehungry_web_user_remember_me` | Persistent login when user opts in | 60 days |

### Analytics (consent required)

| Data | Where stored | Purpose |
|---|---|---|
| `visitor_id` UUID | Session cookie | Anonymous visitor identifier |
| `Meta.Visit` records | PostgreSQL | IP, user agent, path, referrer, page timing — shown in `/professional/analytics` |

### New consent cookie

| Cookie | Key | Values | Lifetime |
|---|---|---|---|
| Consent | `cookie_consent` | `"accepted"` / `"declined"` | 365 days |

Signed server-side (`sign: true, same_site: "Lax"`). Cannot be spoofed by client JS.

---

## Architecture

### New modules

- `MehungryWeb.Plugs.CookieConsent` — reads `cookie_consent` signed cookie, puts `:cookie_consent` assign (`:pending` / `:accepted` / `:declined`) on conn
- `MehungryWeb.ConsentController` — two actions: `POST /cookie-consent/accept` and `POST /cookie-consent/decline`; sets cookie and redirects to referrer
- `MehungryWeb.CookiesPolicyController` — serves `/cookies` static page
- `MehungryWeb.CookiesPolicyHTML` — HTML template for cookie policy

### Modified modules

- `MehungryWeb.VisitorPlug` — early return if `conn.assigns[:cookie_consent] != :accepted`
- `MehungryWeb.Presence` (`maybe_track_user/2`) — early return if socket session consent is not `:accepted`
- `MehungryWeb.Router` — add plug to pipelines, add consent + policy routes
- Layout templates (`root.html.heex`, `live.html.heex`, `landing_live.heex`, `admin_root.heex`) — render `<.cookie_consent_banner />` component
- `MehungryWeb.LayoutView` — add `cookie_consent_banner/1` function component

---

## Data Flow

```
Request arrives
  → Plug.Session reads session cookie (strictly necessary, always)
  → CookieConsentPlug reads cookie_consent cookie
      → absent: assigns :pending
      → "accepted": assigns :accepted
      → "declined": assigns :declined
  → VisitorPlug: no-op unless consent == :accepted
  → Router pipeline + LiveView mount
  → Layout renders banner if consent == :pending (not on /professional/ or /nutritionist/)
  → User clicks Accept or Decline
      → HTML form POST /cookie-consent/accept or /cookie-consent/decline
      → ConsentController sets signed cookie_consent cookie, redirects to referrer
  → Next request: banner does not render, tracking runs (or stays off)
```

For LiveView sessions, `maybe_track_user` reads `cookie_consent` from the LiveView session map (passed from the conn session) to gate tracking after mount.

---

## Consent Plug

```elixir
defmodule MehungryWeb.Plugs.CookieConsent do
  import Plug.Conn

  @cookie "cookie_consent"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])
    status = case conn.cookies[@cookie] do
      "accepted" -> :accepted
      "declined" -> :declined
      _          -> :pending
    end
    conn
    |> assign(:cookie_consent, status)
    |> put_session("cookie_consent", to_string(status))
  end
end
```

Runs in the `:browser` pipeline after `Plug.Session`, before `VisitorPlug`. Writing the status into the session (as a string) makes it available to LiveView mounts via `get_connect_info(socket, :session)` without extra wiring.

---

## Consent Controller

```
POST /cookie-consent/accept  → sets cookie_consent="accepted", redirect back
POST /cookie-consent/decline → sets cookie_consent="declined", redirect back
```

Reads `Referer` header for redirect target; falls back to `/`.  
Cookie options: `sign: true, max_age: 31_536_000, same_site: "Lax"`.  
These routes sit outside any live session (plain `:browser` pipeline only) so the response is a real HTTP redirect — the signed cookie is set correctly.

---

## Banner UI

Rendered as a function component `<.cookie_consent_banner conn={@conn} />` in `layout_view.ex`.  
Only renders when `@conn.assigns[:cookie_consent] == :pending`.  
Excluded from `/professional/*` and `/nutritionist/*` routes (admin/nutritionist users are authenticated; their activity is recorded under their user account).

**Layout:** Fixed bottom bar (`fixed bottom-0 left-0 right-0 z-50`), dark background matching the site footer.

**Content:**
- Left: "We use cookies to keep you logged in and to understand how the site is used. [Cookie Policy](/cookies)"
- Right: two equally prominent buttons (Accept — primary style, Decline — ghost/outline style)
- Buttons are wrapped in a plain HTML `<form>` so they work without JS

**Accessibility:** `role="dialog"`, `aria-label="Cookie consent"`, buttons clearly labelled.

---

## Cookie Policy Page

Route: `GET /cookies` — rendered by `CookiesPolicyController`, no LiveView.

Sections:
1. **Strictly Necessary** — session cookie, what it does, no opt-out
2. **Functional** — remember me cookie, set only when user opts in at login
3. **Analytics** — visitor_id + visit records, what data is collected, how long it's kept
4. **Withdraw consent** — link that POSTs to `/cookie-consent/decline` and redirects back to `/cookies`

---

## Enforcement in VisitorPlug

```elixir
def call(conn, _opts) do
  if conn.assigns[:cookie_consent] == :accepted do
    case get_session(conn, :visitor_id) do
      nil -> put_session(conn, :visitor_id, Ecto.UUID.generate())
      _   -> conn
    end
  else
    conn
  end
end
```

---

## Enforcement in Presence.maybe_track_user

Add a consent check at the top of the `if connected?(socket)` branch. `CookieConsentPlug` writes the consent status into the session (as a string), so it is available via `get_connect_info(socket, :session)`:

```elixir
session = Phoenix.LiveView.get_connect_info(socket, :session) || %{}
consent = Map.get(session, "cookie_consent")

if consent == "accepted" do
  # ... existing tracking logic
end
```

The outer `if connected?(socket)` guard stays; the consent check wraps the tracking block inside it.

---

## Router Changes

```elixir
# In :browser pipeline (after plug :fetch_session)
plug MehungryWeb.Plugs.CookieConsent
# VisitorPlug remains here, after CookieConsent

# New routes (outside live sessions, plain :browser pipeline)
post "/cookie-consent/accept",  ConsentController, :accept
post "/cookie-consent/decline", ConsentController, :decline
get  "/cookies",                CookiesPolicyController, :index
```

---

## Testing

| Test | File | Cases |
|---|---|---|
| `CookieConsentPlug` unit | `test/mehungry_web/plugs/cookie_consent_plug_test.exs` | no cookie → `:pending`; signed "accepted" → `:accepted`; signed "declined" → `:declined`; tampered cookie → `:pending` |
| `VisitorPlug` unit | `test/mehungry_web/visitor_plug_test.exs` (update existing) | skips UUID when `:pending`; skips UUID when `:declined`; assigns UUID when `:accepted` |
| `ConsentController` integration | `test/mehungry_web/controllers/consent_controller_test.exs` | POST accept sets cookie + redirects; POST decline sets cookie + redirects; missing referer falls back to `/` |
| Banner render | `test/mehungry_web/views/layout_view_test.exs` | renders when `:pending`; hidden when `:accepted`; hidden when `:declined` |
