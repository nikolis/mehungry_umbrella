# Personal short handle for nutritionists (`/@handle`)

**Status:** Shipped 2026-10-29. (Originally written as a plan the same day — kept as the design
record; the as-built summary is at the bottom.)

Give each nutritionist a short, brandable, business-card-friendly link — `m3hungry.com/@maria` —
that resolves to their existing public profile. This is a **shareable entry point**, not a new
page: it builds on the profiles described in `professional_profiles.md` and does **not** change
the canonical, SEO-indexed URL (`/nutritionists/:slug`).

## Why a handle (and not just the slug)

Nutritionists already have a public URL today: `/nutritionists/:slug` (locale-prefixed via
`localized_live`, `rel=canonical` to the prefixed form, in the sitemap). The gap is that the
slug is **long, auto-generated, and deliberately stable** (it's the indexed URL — see
`professional_profiles.md`), so it's awkward to print on a card or say out loud. A short handle
is a *different thing*: user-chosen, short, memorable. We keep both — the slug stays the SEO
canonical, the handle is the vanity entry point.

## Decisions

### 1. Route: single-segment catch-all `/:handle`, `@`-gated in the controller

The `@maria` **aesthetic** is what we want, but Phoenix routers can't match an intra-segment
param like `/@:handle` — a dynamic segment must own a whole path segment. So the route is a
plain single-segment `/:handle` declared **last** (lowest priority, GitHub-style vanity URL):
every real single-segment route (`/foods`, `/browse`, `/trial`, …) is declared earlier and
matches first, so the catch-all only ever receives otherwise-unmatched segments. The controller
then honours **only** segments starting with `@` and 404s everything else, so a bare
`/some-word` behaves exactly like an unknown path and the catch-all never "claims" non-handles.

This keeps the exact `/@maria` URL while staying collision-proof. (`localized_live`'s
`/:locale/x` routes are two-segment and so never conflict with a one-segment handle.)

### 2. Behaviour: 301 redirect, never a second rendered page

`/@maria` issues a **301** to the canonical `/:locale/nutritionists/:slug`. Rendering the profile
at the handle too would create duplicate indexable content and split directory-SEO signal. Rules:

- Resolve the profile by `handle`; **404** if unknown or the profile is not `is_public`.
- Preserve locale: redirect to the visitor's resolved locale path (`SetLocale`/`RestoreLocale`
  already resolve it), defaulting to the primary locale when none.
- The handle page is `noindex` / absent from the sitemap — only `/nutritionists/:slug` stays
  canonical and indexed.

Because it's a pure lookup-and-redirect, this is a **controller/plug**, not a LiveView.

### 3. Storage: a new `handle` column, distinct from `slug`

Do **not** overload the existing `slug`. The slug must stay stable (indexed links); a handle is
short, user-chosen, and stricter. Add to `professional_profiles`:

- `handle` — nullable (null = "no short link yet"), `citext` or downcased, with a
  `unique_index`.
- Format `^[a-z0-9_]{3,30}$`.
- A **reserved-words blocklist** (`admin`, `api`, `nutritionists`, `nutritionist`, `foods`,
  `browse`, `profile`, `welcome`, `search`, locale codes `en`/`el`, …) so a handle can never
  mask a real route even inside the `@`-prefixed space.

Mirror the existing slug plumbing: add `:handle` to `ProfessionalProfile.changeset/2` with
format validation + the blocklist check + `unique_constraint(:handle)`, and reuse the
`ensure_unique_slug/unique_slug` pattern in `Professionals` only if we want auto-disambiguation
(for a *user-chosen* handle we likely prefer a hard "already taken" error instead).

## Build outline

1. **Migration** — add `handle` column + unique index to `professional_profiles`.
2. **Schema** — `ProfessionalProfile`: add `:handle` to `@editable_fields`, format validation,
   reserved-word validation, `unique_constraint(:handle)`.
3. **Context** — `Professionals.get_public_professional_by_handle/1` (mirrors
   `get_public_professional_by_slug/1`, gated on `is_public`).
4. **Route + controller** — `get "/@:handle"` → `NutritionistHandleController` (or a small plug):
   look up profile → resolve locale → 301 to `/:locale/nutritionists/:slug`; 404 otherwise.
5. **Editor UI** — add the handle field to `NutritionistLive.ProfileEdit` (`/nutritionist/profile`)
   with a live preview (`m3hungry.com/@___`), "already taken" feedback, and a **"Copy my link"**
   button.
6. **Docs** — update `professional_profiles.md` (add the handle to the Identity fields + a short
   "Personal short link" section) in the same change, per the CLAUDE.md doc-sync rule.

## Cost / sequencing

~Half a day. No new infra. Can ship to all `pro`-tier nutritionists, or gate as a Pro-tier perk.
This is the middle tier of the three URL options discussed; the heavier **custom-domain**
option (`maria-nutrition.com` via CNAME + per-domain TLS on Fly) is deliberately out of scope
here and would be a separate, ops-heavy Pro upsell.

## Out of scope / open questions

- **Handle changes & link rot.** If we let handles be edited freely, printed `/@old` links die.
  Options: (a) treat the handle as set-once, or (b) keep a small `handle_history` table and 301
  old → current. Since the handle only ever *redirects* (never indexed), link-rot is a UX issue,
  not an SEO one — (a) is probably acceptable to start.
- **Reserved-word list source of truth.** Keep it next to the router's top-level route names so
  it doesn't drift as routes are added.

## As built (2026-10-29)

- **Migration** `20261029120000_add_handle_to_professional_profiles` — `handle` string column +
  unique index on `professional_profiles`.
- **Schema** `Mehungry.Professionals.ProfessionalProfile` — `handle` field in `@editable_fields`;
  `normalize_handle/1` (trim + downcase, blank → nil) and `validate_handle/1`
  (`@handle_format` `^[a-z0-9_]{3,30}$` + `@reserved_handles` blocklist) in `changeset/2`, plus
  `unique_constraint(:handle)`.
- **Context** `Mehungry.Professionals.get_public_professional_by_handle/1` — case-insensitive,
  published-only.
- **Route + controller** — last route `get "/:handle"` → `MehungryWeb.NutritionistHandleController`
  (`@`-gated, 301 → `/:locale/nutritionists/:slug` via `MehungryWeb.Locale.detect/1`, else 404).
- **Editor** — "Personal short link" section in `NutritionistLive.ProfileEdit` with a live
  `host/@…` preview + Alpine "Copy link" button (and a "publish to go live" hint when private).
- **Tests** — schema/context cases in `professionals_test.exs`; redirect/404/no-shadow cases in
  `nutritionist_handle_controller_test.exs`.

Deferred as written: editing a handle has no redirect history (handles only ever *redirect*, so
link-rot is a UX concern, not SEO); custom domains remain out of scope.
