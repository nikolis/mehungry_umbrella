# Localization (i18n) — locale-prefixed URLs

How Mehungry serves every page in a per-language URL (`/en/…`, `/el/…`) for
anonymous visitors, logged-in users, and crawlers alike. Covers both **static UI
chrome** (Gettext) and **database content** (the `*_translation` tables), plus the
SEO surface (hreflang, canonical, sitemap).

Supported locales: **`en`** (default) and **`el`**. Add more in one place —
`config :mehungry_web, :locales` in `config/config.exs`.

---

## The big picture

```
Request  /el/browse
   │
   ▼
:browser pipeline ─ MehungryWeb.Plugs.SetLocale
   │   reads /:locale path param → Gettext.put_locale + assign(:locale) + put_session
   ▼
LiveView mount ─ on_mount MehungryWeb.RestoreLocale   (runs before the auth hooks)
   │   re-reads params["locale"] (connected process) → Gettext.put_locale
   │   assign(:locale) AND assign(:current_language)  ← URL is authoritative
   ▼
Render
   ├─ static chrome  → gettext("Browse")            → priv/gettext/el/…/default.po
   ├─ DB content     → Food.get_recipe!(id, @current_language) → *_translation rows
   └─ <head>/<html>  → <html lang="el">, rel=canonical + hreflang alternates
```

**One rule to remember:** the **URL locale is the source of truth**. A user's stored
`language_preference` is only a fallback (for bare, unprefixed URLs) and a persisted
convenience — the path always wins.

---

## Locale vocabulary (the one gotcha)

Two code systems coexist historically:

| Where | Codes | Example |
|---|---|---|
| URLs, user preference, recipe-title translations | lowercase ISO `en` / `el` | `/el/browse`, `RecipeTranslation.language_name == "el"` |
| `languages` rows + ingredient/category/unit translations | legacy `En` / `Gr` | `IngredientTranslation.language_name == "Gr"` |

The bridge is `MehungryWeb.Locale.data_language_name/1` (`"el" → "Gr"`, `"en" → "En"`)
and, in the core app, `Mehungry.Food.Localization.ingredient_language_for/1`
(`"el" → "Gr"`, else `nil`). New code should pass the plain locale (`en`/`el`) around
and let those helpers translate to the data-layer name at the query boundary.

> Core cannot depend on web (umbrella dep direction), so the canonical data mapping
> lives in the **core** app; `MehungryWeb.Locale.data_language_name/1` is the web-side
> mirror.

---

## Components

### `MehungryWeb.Locale` — `apps/mehungry_web/lib/mehungry_web/locale.ex`
Single source of truth. Key functions:

- `supported/0`, `default/0`, `supported?/1` — from `config :mehungry_web, :locales`.
- `detect/1` — Hierarchical Selection over a `conn`: URL param → session → user
  profile → `Accept-Language` → default.
- `swap_path/2` — rewrites the leading path segment to a given locale (inserts one if
  absent, replaces an existing locale, preserves the query string). Powers both the
  language switcher and the SEO alternates. `"/en/foods/x" |> swap_path("el") == "/el/foods/x"`.
- `data_language_name/1` — locale → legacy translation-table language name.

### `MehungryWeb.Plugs.SetLocale` — `plugs/set_locale.ex`
In the `:browser` pipeline (after `:fetch_current_user`). For a `/:locale/…` route it
sets the Gettext locale, assigns `:locale`, and persists it to the session. On a route
with **no** locale segment (login, register, auth callbacks) it still sets a Gettext
locale via `detect/1` but never redirects. A localized route hit with an **unsupported**
locale (`/xx/browse`) is redirected to the same page under the detected/default locale.

> `admin_browser` (used by `/professional/**` and `/nutritionist/**`) does **not** run
> this plug — those surfaces are intentionally English-only, and `@locale` is nil there.

### `MehungryWeb.RestoreLocale` — `live/restore_locale.ex`
`on_mount` hook. The connected LiveView process doesn't run the pipeline, so this
re-establishes `Gettext.put_locale` from `params["locale"]` (falling back to the
session) and assigns `:locale` + `:current_language`. **Listed before** the auth
`on_mount` hooks so their `assign_new(:current_language, …)` becomes a no-op and the URL
wins.

### Router — `router.ex` + `router_helpers.ex`
The `localized_live/3` macro emits each localizable route **twice**: bare (`/browse`) and
prefixed (`/:locale/browse`). This is deliberate:

- Prefixed URLs are the canonical, linked-to form.
- Bare URLs keep working for old bookmarks/inbound links **and** keep every existing
  `~p"/browse"` verified-route literal compiling — so link migration can be incremental.
- Duplicate-content is handled by `rel=canonical` pointing crawlers at the prefixed URL.

Localized live_sessions: `:maybe` (public), `:default3` (`/welcome`), `:default`
(authenticated app). Bare `/` → `HomePageController` redirects to `/{locale}/home` (or
`/welcome`). There is intentionally **no** bare `/:locale` index route (it would greedily
shadow single-segment routes like `/login`).

### Language switcher — `UserLanguageController` + menus
`GET /users/language/:lang` (public — anonymous users can switch). It persists the
preference for logged-in users, then redirects to the **same page** under the new locale
by `swap_path`-ing the referer. The switcher UI lives in
`views/layout/templates/menu/main_menu.html.heex` (shown to everyone now) and nav links
in both `main_menu` and `mobile_menu` are locale-prefixed via `@current_language`.

---

## Static UI strings (Gettext)

Backend: `MehungryWeb.Gettext`. `import MehungryWeb.Gettext` is already in the `:html`,
`:live_view`, and `:controller` quotes, so `gettext("…")` works in any template.

Workflow to add/translate strings:

```bash
cd apps/mehungry_web
# 1. Wrap hardcoded English in gettext("…") in the .heex/.ex
# 2. Extract msgids into the .pot
mix gettext.extract
# 3. Merge into the el locale (creates/updates priv/gettext/el/LC_MESSAGES/default.po)
mix gettext.merge priv/gettext --locale el
# 4. Fill in the Greek `msgstr ""` values, recompile.
```

`en` has no `default.po` on purpose — English falls back to the msgid (the source
string). Locale is already set process-wide by `SetLocale`/`RestoreLocale`, so no
per-call locale is needed.

**Status:** the shared navigation chrome (`main_menu`) is migrated as the worked
example. The remaining ~60 templates follow the identical pattern (see "Remaining work").

---

## Database content

Already localized before this work via per-record `*_translation` tables keyed on a
string `language_name` FK (`Mehungry.Food.Localization`, `docs/food/food.md`). What changed:
content LiveViews now read the language from the **URL locale** (`@current_language`)
rather than only the user's profile. Representative call sites:

- `foods_live`, `food_detail_live`, `species_detail_live`, `calendar_live` — already read
  `socket.assigns[:current_language]`.
- `home_live`, `recipe_browser_live` — updated to prefer `@current_language`, falling back
  to `profile.language_preference`.

`Food.get_recipe!(id, locale)` and `Localization` apply the translation with per-field
fallback to the base record; ingredient/category/unit joins go through the
`"el" → "Gr"` bridge.

### Translation coverage hub (`/professional/translations`)

A single admin surface that tracks and drives DB-content translation across every
user-facing resource. Driven off one declarative registry so all resources share
one code path:

- **Registry** — `Mehungry.Languages.TranslationRegistry` lists a descriptor per
  resource (base schema, `*_translation` schema, FK, translatable fields, AI mode).
  Covered today: recipes, ingredients, measurement units, categories, food species,
  food products, **compounds, health conditions, nutrients** (the last three got new
  `*_translation` tables in this work).
- **Every translation row carries a `status`** (`"ai_draft"` | `"verified"`) plus
  `verified_at`/`verified_by_id`. Pre-existing rows were backfilled `"verified"`.
- **Coverage** — `Mehungry.Languages.Coverage.stats/0` reports, per resource × target
  locale, `verified`/`ai_draft`/`missing` counts + a verified `pct` (e.g. "Ingredients
  EL: 62%"). A base row counts *verified* if any verified translation exists, *ai_draft*
  if only a draft exists, else *missing*.
- **Generic ops** — `Mehungry.Languages.Translations.{list_items, get_pair, upsert,
  verify, missing_ids}` read/write any `*_translation` table from a descriptor.
- **AI** — `Mehungry.AI.FieldTranslator` (generic field maps) + `AI.RecipeTranslator`
  (structured steps). Per-item "AI Translate → review → Save & Verify", or bulk
  "AI-translate all missing" via `ObanWorkers.ResourceTranslationWorker` (`:ai_agents`
  queue) which writes `ai_draft`s for a human to confirm.
- **Locale codes** — `Mehungry.Languages.Locale` is the core-side twin of
  `MehungryWeb.Locale`: new rows are written under the ISO code (`"el"`), while coverage
  counts **both** ISO and legacy codes (`["el", "Gr"]`) so pre-existing `Gr` rows still
  count. Normalizing the legacy `Gr`↔`el` split in the data is a sensible follow-up.
- **UI** — `MehungryWeb.ProfessionalLive.TranslationsLive.{Index, Panel}` (coverage
  grid + per-resource panel), linked from the admin sidebar.

---

## SEO

- **`<html lang={locale}>`** — `views/layout/templates/root.html.heex`.
- **Canonical + hreflang** — `templates/head.html.heex` emits a locale-prefixed
  `rel=canonical` and one `<link rel="alternate" hreflang>` per supported locale plus
  `x-default` (only on indexable, `@locale`-bearing pages).
- **Sitemap** — `SitemapController` emits each content URL once per locale, each carrying
  reciprocal `xhtml:link` hreflang alternates (`urlset` gains the `xhtml` namespace).

See also `docs/seo.md`.

---

## Testing

- `apps/mehungry_web/test/mehungry_web/locale_test.exs` — `Locale` unit tests
  (`supported?`, `swap_path`, `data_language_name`).
- `apps/mehungry_web/test/mehungry_web/locale_routing_test.exs` — end-to-end:
  `/` → `/en/welcome`; `/el/welcome` sets the session locale; `/xx/…` redirects to
  default; bare paths still resolve; language switch swaps the referer's prefix; and a
  localized page renders `<html lang="el">` + the Greek menu label + hreflang.

```bash
mix test apps/mehungry_web/test/mehungry_web/locale_test.exs \
         apps/mehungry_web/test/mehungry_web/locale_routing_test.exs
```

---

## Adding a new locale

1. Add the code to `config :mehungry_web, :locales` (`supported`) in `config/config.exs`.
2. Seed a matching `languages` row + a `data_language_name/1` clause if the data tables
   use a legacy code (or reuse the ISO code for new translation rows).
3. `mix gettext.merge priv/gettext --locale <code>` and translate the `.po`.
4. Add the pill to the menu switcher (`main_menu.html.heex`).
5. Backfill `*_translation` rows for the content you want localized.

---

## Remaining work (follow-up)

- **Gettext**: wrap hardcoded English in the remaining ~60 templates and translate; the
  menu is the reference implementation.
- **`~p` links**: deep in-page links still use bare `~p"/…"`. They *work* (both-paths
  routes + canonical), but migrate to `~p"/#{@locale}/…"` for prefix-consistent URLs.
- **Optional**: a language toggle in the compact mobile bottom-nav; consolidating the
  `el↔Gr` mapping so core and web share one definition.
