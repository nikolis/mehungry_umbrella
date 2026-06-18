# Cookie Consent Banner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GDPR-compliant sticky bottom banner that gates visitor analytics tracking behind explicit user consent, stored in a 365-day signed cookie.

**Architecture:** A new `CookieConsentPlug` runs early in both browser pipelines, reads the `cookie_consent` signed cookie, assigns `:pending`/`:accepted`/`:declined` on the conn, and mirrors the status into the session so LiveView layouts can read it. `VisitorPlug` and `Presence.maybe_track_user` check for `:accepted` before recording any analytics. Two plain controller actions write the signed cookie on Accept/Decline and redirect back. The banner is a function component rendered in `root.html.heex` only (admin/nutritionist routes use `admin_root.heex` which does not get the banner).

**Tech Stack:** Elixir/Phoenix, Plug, Phoenix LiveView, Tailwind CSS + DaisyUI, ExUnit + ConnCase

## Global Constraints

- Signed cookies use `sign: true, same_site: "Lax"` — never plain text
- Cookie name: `cookie_consent`, values: `"accepted"` / `"declined"`
- Consent cookie max age: `31_536_000` seconds (365 days)
- Session key: `"cookie_consent"` (string key, not atom), value is the string form of the atom (`"accepted"` / `"declined"` / `"pending"`)
- `CookieConsentPlug` must run after `plug :fetch_session` and before `MehungryWeb.VisitorPlug` in every pipeline that includes `VisitorPlug`
- No JS required — banner buttons are plain HTML forms
- Run tests with: `mix test apps/mehungry_web/test/` from the umbrella root

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `apps/mehungry_web/lib/mehungry_web/plugs/cookie_consent.ex` | Read signed cookie → assign + session |
| Create | `apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs` | Plug unit tests |
| Modify | `apps/mehungry_web/lib/mehungry_web/visitor_plug.ex` | Gate UUID on `:accepted` |
| Create | `apps/mehungry_web/test/mehungry_web/visitor_plug_test.exs` | VisitorPlug unit tests |
| Create | `apps/mehungry_web/lib/mehungry_web/controllers/consent_controller.ex` | Accept / Decline actions |
| Create | `apps/mehungry_web/test/mehungry_web/controllers/consent_controller_test.exs` | Controller integration tests |
| Modify | `apps/mehungry_web/lib/mehungry_web/router.ex` | Add plug to pipelines + routes |
| Create | `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_controller.ex` | /cookies static page |
| Create | `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html.ex` | HTML view module |
| Create | `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html/index.html.heex` | Cookie policy template |
| Modify | `apps/mehungry_web/lib/mehungry_web/views/layout/layout_view.ex` | Add `cookie_consent_banner/1` component |
| Modify | `apps/mehungry_web/lib/mehungry_web/views/layout/templates/root.html.heex` | Render banner |
| Modify | `apps/mehungry_web/lib/mehungry_web/presence.ex` | Gate `maybe_track_user` on consent |

---

### Task 1: CookieConsent Plug

**Files:**
- Create: `apps/mehungry_web/lib/mehungry_web/plugs/cookie_consent.ex`
- Create: `apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs`

**Interfaces:**
- Produces: `conn.assigns[:cookie_consent]` — atom `:pending`, `:accepted`, or `:declined`
- Produces: session key `"cookie_consent"` — string `"pending"`, `"accepted"`, or `"declined"`
- Consumes: signed request cookie `"cookie_consent"` — written by `ConsentController` (Task 3)

- [ ] **Step 1: Write the failing tests**

Create `apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs`:

```elixir
defmodule MehungryWeb.Plugs.CookieConsentTest do
  use MehungryWeb.ConnCase, async: true

  alias MehungryWeb.Plugs.CookieConsent

  describe "call/2" do
    test "assigns :pending when cookie is absent" do
      conn =
        build_conn()
        |> init_test_session(%{})
        |> CookieConsent.call([])

      assert conn.assigns[:cookie_consent] == :pending
      assert get_session(conn, "cookie_consent") == "pending"
    end

    test "assigns :accepted and writes session after Accept POST + recycle" do
      conn1 =
        build_conn()
        |> post("/cookie-consent/accept")

      conn2 =
        conn1
        |> recycle()
        |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :accepted
      assert get_session(conn2, "cookie_consent") == "accepted"
    end

    test "assigns :declined and writes session after Decline POST + recycle" do
      conn1 =
        build_conn()
        |> post("/cookie-consent/decline")

      conn2 =
        conn1
        |> recycle()
        |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :declined
      assert get_session(conn2, "cookie_consent") == "declined"
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs
```

Expected: compilation error (module not found).

- [ ] **Step 3: Create the plug**

Create `apps/mehungry_web/lib/mehungry_web/plugs/cookie_consent.ex`:

```elixir
defmodule MehungryWeb.Plugs.CookieConsent do
  import Plug.Conn

  @cookie "cookie_consent"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn, signed: [@cookie])

    status =
      case conn.cookies[@cookie] do
        "accepted" -> :accepted
        "declined" -> :declined
        _ -> :pending
      end

    conn
    |> assign(:cookie_consent, status)
    |> put_session("cookie_consent", to_string(status))
  end
end
```

- [ ] **Step 4: Run tests — expect 1 pass, 2 fail (ConsentController not yet wired)**

```bash
mix test apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs
```

Expected: `assigns :pending when cookie is absent` passes; the two recycle-based tests fail because the POST routes don't exist yet. This is correct — those tests will pass after Task 3.

- [ ] **Step 5: Commit**

```bash
git add apps/mehungry_web/lib/mehungry_web/plugs/cookie_consent.ex \
        apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs
git commit -m "feat: add CookieConsentPlug — reads signed cookie, assigns status + writes to session"
```

---

### Task 2: Gate VisitorPlug on consent

**Files:**
- Modify: `apps/mehungry_web/lib/mehungry_web/visitor_plug.ex`
- Create: `apps/mehungry_web/test/mehungry_web/visitor_plug_test.exs`

**Interfaces:**
- Consumes: `conn.assigns[:cookie_consent]` — produced by `CookieConsentPlug` (Task 1)
- Produces: session key `:visitor_id` — UUID string, only when consent is `:accepted`

- [ ] **Step 1: Write the failing tests**

Create `apps/mehungry_web/test/mehungry_web/visitor_plug_test.exs`:

```elixir
defmodule MehungryWeb.VisitorPlugTest do
  use MehungryWeb.ConnCase, async: true

  alias MehungryWeb.VisitorPlug

  defp conn_with_consent(status) do
    build_conn()
    |> init_test_session(%{})
    |> assign(:cookie_consent, status)
  end

  describe "call/2 with consent :accepted" do
    test "assigns a visitor_id UUID to the session" do
      conn = conn_with_consent(:accepted) |> VisitorPlug.call([])
      visitor_id = get_session(conn, :visitor_id)
      assert is_binary(visitor_id)
      assert String.length(visitor_id) == 36
    end

    test "preserves an existing visitor_id" do
      existing_id = Ecto.UUID.generate()

      conn =
        conn_with_consent(:accepted)
        |> put_session(:visitor_id, existing_id)
        |> VisitorPlug.call([])

      assert get_session(conn, :visitor_id) == existing_id
    end
  end

  describe "call/2 with consent :pending" do
    test "does not assign a visitor_id" do
      conn = conn_with_consent(:pending) |> VisitorPlug.call([])
      assert get_session(conn, :visitor_id) == nil
    end
  end

  describe "call/2 with consent :declined" do
    test "does not assign a visitor_id" do
      conn = conn_with_consent(:declined) |> VisitorPlug.call([])
      assert get_session(conn, :visitor_id) == nil
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test apps/mehungry_web/test/mehungry_web/visitor_plug_test.exs
```

Expected: "assigns a visitor_id UUID" passes (current plug always assigns), consent-gated tests fail.

- [ ] **Step 3: Update VisitorPlug**

Replace the entire content of `apps/mehungry_web/lib/mehungry_web/visitor_plug.ex`:

```elixir
defmodule MehungryWeb.VisitorPlug do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:cookie_consent] == :accepted do
      case get_session(conn, :visitor_id) do
        nil -> put_session(conn, :visitor_id, Ecto.UUID.generate())
        _ -> conn
      end
    else
      conn
    end
  end
end
```

- [ ] **Step 4: Run tests — all should pass**

```bash
mix test apps/mehungry_web/test/mehungry_web/visitor_plug_test.exs
```

Expected: 4 tests, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add apps/mehungry_web/lib/mehungry_web/visitor_plug.ex \
        apps/mehungry_web/test/mehungry_web/visitor_plug_test.exs
git commit -m "feat: gate VisitorPlug on cookie consent — skips UUID when pending or declined"
```

---

### Task 3: ConsentController + router wiring

**Files:**
- Create: `apps/mehungry_web/lib/mehungry_web/controllers/consent_controller.ex`
- Modify: `apps/mehungry_web/lib/mehungry_web/router.ex`
- Create: `apps/mehungry_web/test/mehungry_web/controllers/consent_controller_test.exs`

**Interfaces:**
- Produces: signed response cookie `"cookie_consent"` with value `"accepted"` or `"declined"`
- Produces: 302 redirect to `Referer` header or `/`
- Consumes: nothing from prior tasks (standalone controller)

- [ ] **Step 1: Write the failing tests**

Create `apps/mehungry_web/test/mehungry_web/controllers/consent_controller_test.exs`:

```elixir
defmodule MehungryWeb.ConsentControllerTest do
  use MehungryWeb.ConnCase, async: true

  describe "POST /cookie-consent/accept" do
    test "sets signed cookie_consent=accepted and redirects to /" do
      conn = post(build_conn(), "/cookie-consent/accept")

      assert redirected_to(conn) == "/"
      cookie = conn.resp_cookies["cookie_consent"]
      assert cookie[:value] == "accepted"
      assert cookie[:max_age] == 31_536_000
    end

    test "redirects to Referer when present" do
      conn =
        build_conn()
        |> put_req_header("referer", "/browse")
        |> post("/cookie-consent/accept")

      assert redirected_to(conn) == "/browse"
    end
  end

  describe "POST /cookie-consent/decline" do
    test "sets signed cookie_consent=declined and redirects to /" do
      conn = post(build_conn(), "/cookie-consent/decline")

      assert redirected_to(conn) == "/"
      cookie = conn.resp_cookies["cookie_consent"]
      assert cookie[:value] == "declined"
      assert cookie[:max_age] == 31_536_000
    end
  end

  describe "cookie persists across requests" do
    test "assign is :accepted on next request after accept" do
      conn1 = post(build_conn(), "/cookie-consent/accept")
      conn2 = recycle(conn1) |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :accepted
    end

    test "assign is :declined on next request after decline" do
      conn1 = post(build_conn(), "/cookie-consent/decline")
      conn2 = recycle(conn1) |> get("/welcome")

      assert conn2.assigns[:cookie_consent] == :declined
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test apps/mehungry_web/test/mehungry_web/controllers/consent_controller_test.exs
```

Expected: compile error or routing error — routes and controller don't exist yet.

- [ ] **Step 3: Create ConsentController**

Create `apps/mehungry_web/lib/mehungry_web/controllers/consent_controller.ex`:

```elixir
defmodule MehungryWeb.ConsentController do
  use MehungryWeb, :controller

  @cookie "cookie_consent"
  @cookie_opts [sign: true, max_age: 31_536_000, same_site: "Lax"]

  def accept(conn, _params) do
    conn
    |> put_resp_cookie(@cookie, "accepted", @cookie_opts)
    |> redirect(to: referer_or_root(conn))
  end

  def decline(conn, _params) do
    conn
    |> put_resp_cookie(@cookie, "declined", @cookie_opts)
    |> redirect(to: referer_or_root(conn))
  end

  defp referer_or_root(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> URI.parse(referer).path || "/"
      [] -> "/"
    end
  end
end
```

- [ ] **Step 4: Wire CookieConsentPlug and new routes into router**

In `apps/mehungry_web/lib/mehungry_web/router.ex`, make these two changes:

**Change 1** — Add `CookieConsentPlug` to the `:browser` pipeline (after `fetch_session`, before `VisitorPlug`):

```elixir
  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug MehungryWeb.Plugs.CookieConsent      # add this line
    plug MehungryWeb.VisitorPlug
    plug Plug.CSRFProtection
    plug :fetch_live_flash
    plug :put_root_layout, {MehungryWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_path_info
    plug :fetch_current_user
  end
```

**Change 2** — Add `CookieConsentPlug` to the `:admin_browser` pipeline (same position):

```elixir
  pipeline :admin_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug MehungryWeb.Plugs.CookieConsent      # add this line
    plug MehungryWeb.VisitorPlug
    plug :fetch_live_flash
    plug :put_root_layout, {MehungryWeb.LayoutView, :admin_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_path_info
    plug :fetch_current_user
  end
```

**Change 3** — Add the consent routes in the existing `scope "/", MehungryWeb` block that uses `pipe_through [:browser]` (the one containing `/privacy_policy`, `/health`, `/sitemap.xml`):

```elixir
  scope "/", MehungryWeb do
    pipe_through [:browser]

    live "/privacy_policy", PrivacyPolicyLive, :index
    get "/health", HealthController, :check
    get "/sitemap.xml", SitemapController, :index
    post "/cookie-consent/accept", ConsentController, :accept   # add this line
    post "/cookie-consent/decline", ConsentController, :decline  # add this line
    get  "/cookies", CookiesPolicyController, :index             # add this line
  end
```

- [ ] **Step 5: Run the tests**

```bash
mix test apps/mehungry_web/test/mehungry_web/controllers/consent_controller_test.exs
```

Expected: 5 tests, 0 failures.

- [ ] **Step 6: Run the plug tests too — all 3 should now pass**

```bash
mix test apps/mehungry_web/test/mehungry_web/plugs/cookie_consent_test.exs
```

Expected: 3 tests, 0 failures (the recycle-based tests now pass since routes exist).

- [ ] **Step 7: Commit**

```bash
git add apps/mehungry_web/lib/mehungry_web/controllers/consent_controller.ex \
        apps/mehungry_web/lib/mehungry_web/router.ex \
        apps/mehungry_web/test/mehungry_web/controllers/consent_controller_test.exs
git commit -m "feat: add ConsentController and wire CookieConsentPlug into browser pipelines"
```

---

### Task 4: Cookie policy page

**Files:**
- Create: `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_controller.ex`
- Create: `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html.ex`
- Create: `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html/index.html.heex`

**Interfaces:**
- Route `GET /cookies` already added to router in Task 3
- Consumes: nothing from prior tasks

- [ ] **Step 1: Create the controller**

Create `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_controller.ex`:

```elixir
defmodule MehungryWeb.CookiesPolicyController do
  use MehungryWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
```

- [ ] **Step 2: Create the HTML view module**

Create `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html.ex`:

```elixir
defmodule MehungryWeb.CookiesPolicyHTML do
  use MehungryWeb, :html

  embed_templates "cookies_policy_html/*"
end
```

- [ ] **Step 3: Create the template directory and template file**

```bash
mkdir -p apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html
```

Create `apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html/index.html.heex`:

```html
<div class="max-w-3xl mx-auto px-6 py-16 text-slate-200">
  <h1 class="text-3xl font-semibold mb-2">Cookie Policy</h1>
  <p class="text-sm text-slate-400 mb-10">Last updated: June 2026</p>

  <section class="mb-10">
    <h2 class="text-xl font-semibold mb-3">1. Strictly Necessary Cookies</h2>
    <p class="text-slate-300 mb-3">
      These cookies are required for the site to function. They cannot be switched off.
    </p>
    <table class="w-full text-sm border-collapse">
      <thead>
        <tr class="border-b border-slate-700">
          <th class="text-left py-2 pr-4 text-slate-400">Cookie</th>
          <th class="text-left py-2 pr-4 text-slate-400">Purpose</th>
          <th class="text-left py-2 text-slate-400">Expires</th>
        </tr>
      </thead>
      <tbody>
        <tr class="border-b border-slate-800">
          <td class="py-2 pr-4 font-mono text-xs">_mehungry_web_key</td>
          <td class="py-2 pr-4">Keeps you logged in and protects against request forgery</td>
          <td class="py-2">Session</td>
        </tr>
      </tbody>
    </table>
  </section>

  <section class="mb-10">
    <h2 class="text-xl font-semibold mb-3">2. Functional Cookies</h2>
    <p class="text-slate-300 mb-3">
      Set only when you explicitly choose "Remember me" at login.
    </p>
    <table class="w-full text-sm border-collapse">
      <thead>
        <tr class="border-b border-slate-700">
          <th class="text-left py-2 pr-4 text-slate-400">Cookie</th>
          <th class="text-left py-2 pr-4 text-slate-400">Purpose</th>
          <th class="text-left py-2 text-slate-400">Expires</th>
        </tr>
      </thead>
      <tbody>
        <tr class="border-b border-slate-800">
          <td class="py-2 pr-4 font-mono text-xs">_mehungry_web_user_remember_me</td>
          <td class="py-2 pr-4">Keeps you logged in across browser restarts</td>
          <td class="py-2">60 days</td>
        </tr>
      </tbody>
    </table>
  </section>

  <section class="mb-10">
    <h2 class="text-xl font-semibold mb-3">3. Analytics Cookies</h2>
    <p class="text-slate-300 mb-3">
      Used to understand how visitors use the site. All data is processed internally — we do not share it with any third party.
    </p>
    <table class="w-full text-sm border-collapse">
      <thead>
        <tr class="border-b border-slate-700">
          <th class="text-left py-2 pr-4 text-slate-400">Data</th>
          <th class="text-left py-2 pr-4 text-slate-400">Purpose</th>
          <th class="text-left py-2 text-slate-400">Retention</th>
        </tr>
      </thead>
      <tbody>
        <tr class="border-b border-slate-800">
          <td class="py-2 pr-4 font-mono text-xs">visitor_id (session)</td>
          <td class="py-2 pr-4">Anonymous identifier to count unique visitors</td>
          <td class="py-2">Session</td>
        </tr>
        <tr class="border-b border-slate-800">
          <td class="py-2 pr-4 font-mono text-xs">Visit records (database)</td>
          <td class="py-2 pr-4">IP address, browser type, page visited, referrer, page load time</td>
          <td class="py-2">90 days</td>
        </tr>
      </tbody>
    </table>
    <p class="text-sm text-slate-400 mt-3">
      These are only set if you click <strong>Accept</strong> on the cookie banner.
    </p>
  </section>

  <section class="mb-10">
    <h2 class="text-xl font-semibold mb-3">4. Withdraw Consent</h2>
    <p class="text-slate-300 mb-4">
      You can withdraw your analytics consent at any time. This stops all future visit recording and removes your visitor identifier from your session.
    </p>
    <form action="/cookie-consent/decline" method="post">
      <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
      <input type="hidden" name="_method" value="post" />
      <button
        type="submit"
        class="btn btn-outline btn-sm border-slate-600 text-slate-300 hover:bg-slate-700"
      >
        Withdraw analytics consent
      </button>
    </form>
  </section>
</div>
```

- [ ] **Step 4: Verify the page compiles and renders**

```bash
mix phx.server
```

Open `http://localhost:4000/cookies` in a browser. Confirm the page renders with all four sections. Stop the server with Ctrl-C.

- [ ] **Step 5: Commit**

```bash
git add apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_controller.ex \
        apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html.ex \
        apps/mehungry_web/lib/mehungry_web/controllers/cookies_policy_html/index.html.heex
git commit -m "feat: add /cookies policy page"
```

---

### Task 5: Banner component + root layout

**Files:**
- Modify: `apps/mehungry_web/lib/mehungry_web/views/layout/layout_view.ex`
- Modify: `apps/mehungry_web/lib/mehungry_web/views/layout/templates/root.html.heex`

**Interfaces:**
- Consumes: `conn.assigns[:cookie_consent]` — atom from `CookieConsentPlug`
- Produces: rendered banner HTML when status is `:pending`

- [ ] **Step 1: Add the banner component to LayoutView**

Open `apps/mehungry_web/lib/mehungry_web/views/layout/layout_view.ex`. Add the following function component anywhere after the existing `attr` declarations near the top of the module (before `get_menu/1`):

```elixir
  attr :conn, :any, required: true

  def cookie_consent_banner(assigns) do
    ~H"""
    <%= if @conn.assigns[:cookie_consent] == :pending do %>
      <div
        id="cookie-consent-banner"
        role="dialog"
        aria-label="Cookie consent"
        class="fixed bottom-0 left-0 right-0 z-50 flex flex-col gap-3 border-t border-slate-700 bg-slate-900/95 px-4 py-4 backdrop-blur-sm sm:flex-row sm:items-center sm:justify-between sm:px-8"
      >
        <p class="text-sm text-slate-300">
          We use cookies to keep you logged in and to understand how the site is used.
          <a href="/cookies" class="ml-1 underline hover:text-white">Cookie Policy</a>
        </p>
        <div class="flex shrink-0 gap-3">
          <form action="/cookie-consent/decline" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button type="submit" class="btn btn-sm btn-ghost border border-slate-600 text-slate-300 hover:bg-slate-700">
              Decline
            </button>
          </form>
          <form action="/cookie-consent/accept" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button type="submit" class="btn btn-sm btn-primary">
              Accept
            </button>
          </form>
        </div>
      </div>
    <% end %>
    """
  end
```

- [ ] **Step 2: Render the banner in root.html.heex**

Open `apps/mehungry_web/lib/mehungry_web/views/layout/templates/root.html.heex`. Replace its content with:

```html
<!DOCTYPE html>
<html lang="en" class="snap-y	snap-mandatory">
  <!-- Favicon - SVG for modern browsers -->
  <.head conn={@conn} />
  <body>
    {@inner_content}
    <.cookie_consent_banner conn={@conn} />
    <.footer />
  </body>
</html>
```

- [ ] **Step 3: Verify banner renders on a fresh browser session**

```bash
mix phx.server
```

1. Open a private/incognito browser window and go to `http://localhost:4000/welcome`
2. Confirm the banner appears at the bottom
3. Click **Accept** — confirm the banner disappears and you're redirected back
4. Reload — confirm the banner is gone
5. Open a new private window, go to `http://localhost:4000/welcome`, click **Decline** — confirm the banner disappears
6. Reload — confirm the banner stays gone

Stop the server with Ctrl-C.

- [ ] **Step 4: Commit**

```bash
git add apps/mehungry_web/lib/mehungry_web/views/layout/layout_view.ex \
        apps/mehungry_web/lib/mehungry_web/views/layout/templates/root.html.heex
git commit -m "feat: add cookie consent banner to root layout"
```

---

### Task 6: Gate Presence tracking on consent

**Files:**
- Modify: `apps/mehungry_web/lib/mehungry_web/presence.ex`

**Interfaces:**
- Consumes: session key `"cookie_consent"` (string) read via `get_connect_info(socket, :session)` — written by `CookieConsentPlug` (Task 1)
- No new files; no new tests (Presence tracking is internal analytics, validated by observing the `Meta.Visit` table and `/professional/analytics` dashboard)

- [ ] **Step 1: Update maybe_track_user in presence.ex**

In `apps/mehungry_web/lib/mehungry_web/presence.ex`, locate the `maybe_track_user/2` function inside the `quote do` block. The `if connected?(socket) do` branch currently starts by deriving `{address, agent}`. Add a consent check at the very top of that branch.

The current structure is:
```elixir
def maybe_track_user(product, socket) do
  if connected?(socket) do
    {address, agent} =
      case get_address_agent(socket) do
        ...
      end
    ...
    {user_token, visitor_id} =
      try do
        session = Phoenix.LiveView.get_connect_info(socket, :session) || %{}
        {Map.get(session, "user_token"), Map.get(session, "visitor_id")}
      rescue
        _ -> {nil, nil}
      end
    ...
  else
    nil
  end
end
```

Replace the entire `def maybe_track_user(product, socket) do` function with:

```elixir
def maybe_track_user(product, socket) do
  if connected?(socket) do
    session = Phoenix.LiveView.get_connect_info(socket, :session) || %{}
    consent = Map.get(session, "cookie_consent")

    if consent == "accepted" do
      {address, agent} =
        case get_address_agent(socket) do
          {a, ag} -> {a, ag}
          _ -> {Map.get(socket.assigns, :address, ""), Map.get(socket.assigns, :agent, "")}
        end

      referrer = Map.get(socket.assigns, :referrer, "")
      path = Map.get(socket.assigns, :path, "")
      current_user = Map.get(socket.assigns, :current_user)

      {user_token, visitor_id} =
        try do
          {Map.get(session, "user_token"), Map.get(session, "visitor_id")}
        rescue
          _ -> {nil, nil}
        end

      session_key =
        if user_token do
          :crypto.hash(:sha256, user_token)
          |> Base.encode16(case: :lower)
          |> String.slice(0, 24)
        else
          date = Date.utc_today() |> Date.to_string()
          :crypto.hash(:sha256, "#{address}|#{agent}|#{date}")
          |> Base.encode16(case: :lower)
          |> String.slice(0, 24)
        end

      ret =
        Presence.track(self(), "general", "general", %{
          address: address,
          agent: agent,
          path: path
        })

      case Mehungry.Meta.create_visit(%{
             ip_address: address,
             session_key: session_key,
             details: %{
               agent: agent,
               path: path,
               referrer: referrer,
               visitor_id: visitor_id,
               user_id: current_user && current_user.id,
               user_email: current_user && current_user.email
             }
           }) do
        {:ok, visit} -> Process.put(:current_visit_id, visit.id)
        _ -> :ok
      end

      Phoenix.PubSub.broadcast(Mehungry.PubSub, "mehungry:analytics", :new_visit)

      ret
    end
  else
    nil
  end
end
```

Note: the inner `if consent == "accepted"` returns `nil` implicitly when false, matching the existing `nil` return in the `else` branch.

- [ ] **Step 2: Compile and verify no errors**

```bash
mix compile
```

Expected: 0 errors, 0 warnings (or only pre-existing warnings).

- [ ] **Step 3: Run full test suite**

```bash
mix test apps/mehungry_web/test/
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add apps/mehungry_web/lib/mehungry_web/presence.ex
git commit -m "feat: gate Presence visit tracking on cookie consent"
```

---

## Final Verification

- [ ] Run the complete test suite one more time:
  ```bash
  mix test apps/mehungry_web/test/
  ```
- [ ] Start the server and smoke-test end-to-end:
  ```bash
  mix phx.server
  ```
  1. Open incognito — banner appears on `/welcome`, `/browse`, `/home`
  2. Banner does **not** appear on `/professional/*`
  3. Accept → banner gone, page reload → still gone
  4. Open new incognito → Decline → banner gone, analytics not recorded
  5. `/cookies` page renders all four sections, "Withdraw" button works
