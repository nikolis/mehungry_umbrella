# Design system

Status as of 2026-07-20: rolled out across the entire customer-facing app —
`/profile` (the original pilot), the nav shell (desktop sidebar + mobile bottom
nav + top bar), `/basket`, `/calendar`, `/create_recipe` + `/stepper`,
`/browse` + `/search`, `/home` (feed and post cards), `/foods` +
`/foods/:slug`, recipe detail (`/home/:id`, `/browse/:id`, `/show_recipe/:id`,
including the social-media share flow), `/feedback`, `/upgrade`, `/welcome`
(landing), and the login/register pages. `recipe_card` and the sidebar/root
layout's DOM structure were deliberately left alone per the original scope
notes below (only their colors changed where they inherited from the shell).

**Not yet migrated (still old navy/slate/orange):** everything under
`/professional/**` (admin tools — AI bot review, analytics, ingredients, S3
browser, SEO, maintenance, etc.) and `/nutritionist/**` (dashboard, clients,
appointments). These are internal/lower-visual-priority screens on separate
layout templates (`admin_root.heex`/`admin_live.heex`,
`nutritionist_live.heex`) and were explicitly deferred — see "Next candidates"
below. This doc exists so the next pass picks up the same direction instead of
drifting.

## Why this direction

Mehungry's own pitch is *"168 nutrients tracked, from real USDA data, not
estimated."* That claim showed up once, on `/welcome`, and nowhere inside the
actual product. Meanwhile `tailwind.config.js` already defined a `primary`
(orange), `secondary` (teal), and `accent` (purple) — but every screen only
ever drew from orange, so every button (Save, Upgrade, Delete Account) carried
identical visual weight and nothing signaled hierarchy.

Two changes follow from that:

1. **Give the unused teal a real job.** It's now the dedicated color for *any
   number in the app* — recipe meta, profile stats, nutrient values, quota
   counters. Orange means action/social. Teal means data. Numbers are the one
   thing Mehungry can say nobody else can, so they get their own consistent
   visual identity instead of blending into body text.
2. **Warm the base palette.** Blue-black (`slate-900`) reads as generic SaaS
   dashboard, not food. Swapped for a warm charcoal so the app reads as a
   kitchen, not a ticketing tool.

Full writeup and before/after component mockups:
[Mehungry Visual Identity Proposal](https://claude.ai/code/artifact/da653f54-b9fc-446a-8bc5-ead5a833394a)
(Claude artifact — palette rationale, type pairing, button-hierarchy and
recipe-card comparisons).

## Tokens (`tailwind.config.js`)

Additive only — nothing existing was removed, so old classes (`bg-slate-800`,
`text-primary-500`, etc.) still work unchanged on pages not yet migrated.

| Token | Hex | Role |
|---|---|---|
| `ink` | `#17140F` | Page background |
| `ink-panel` | `#211D16` | Card / panel surface |
| `ink-panel2` | `#2B2619` | Raised surface, borders, chip backgrounds |
| `paprika` | `#E8622C` | **Action only.** One solid `bg-paprika` primary button per screen |
| `paprika-soft` | `#F0906B` | Hover state for paprika, secondary ghost-link accent |
| `basil` | `#45C4AE` | **Data only.** Every number: stats, recipe meta, nutrient values |
| `basil-soft` | `#8FDDCE` | Basil hover/emphasis variant |
| `parchment` | `#F4EEDD` | Primary text on dark |
| `parchment-dim` | `#A9A08C` | Secondary text, labels, de-emphasized nav links |

`fontFamily.display`: `"Iowan Old Style", "Palatino Linotype", "Book Antiqua",
Georgia, serif` — a system serif stack (no webfont, no CDN, nothing to load).
Use `font-display` for recipe titles, card/section headings, anything that
should read like a recipe card rather than a form label. Body copy, form
inputs, and UI chrome keep the existing system sans (`font-family: var(--ff-base)` /
Tailwind default) — don't introduce a second body face.

Numbers get `[font-variant-numeric:tabular-nums]` + `text-basil` +
`font-bold`, consistently, wherever they appear.

## Component rules

**One primary action per screen.** Everything that isn't the primary action
is a ghost/text-level control (`text-parchment-dim hover:text-parchment`, no
border, no fill). Destructive actions (Delete Account) are quiet — small,
muted red text, never a prominent pill. See `show.html.heex` action row for
the reference implementation.

**Cards, not floating fields.** Group related inputs/rows inside a bordered
container (`border border-ink-panel2`, subtle `bg-black/20` fill) rather than
letting them sit directly on the page background. See
`form_category_component.ex` for the dietary-restriction row pattern.

**Don't force scroll containers around anything that can pop out a dropdown
or tooltip.** `overflow` on an ancestor clips absolutely-positioned
descendants regardless of z-index. If a list is realistically short, let it
flow with the page instead of boxing it in `max-h-*/overflow-y-auto`.

## Retheming a shared component without breaking its other call sites

`SelectComponent` (`apps/mehungry_web/lib/mehungry_web/components/select_component/select_component.ex`)
is used on `/profile`, `/create_recipe`, ingredient search, and more. It
cannot be reskinned by editing its Tailwind classes directly — that would
change every page it's used on.

The pattern used instead: swap the hardcoded color class for an arbitrary
value bound to a CSS custom property with the original color as fallback —

```heex
class="... bg-[var(--sc-bg,#334155)] border-[var(--sc-border,#475569)] ..."
```

— then set that variable only inside the container that wants the new look:

```css
/* profile.css */
.profile-form {
  --sc-bg: #2B2619;
  --sc-border: #3A3323;
  /* ... */
}
```

Everywhere else, the variable is unset, so the component falls back to its
original slate colors. Same technique for the shared `<.input>` /
`<.textarea>` core components: they're scoped under `.profile-form` in
`apps/mehungry_web/assets/css/profile.css` rather than edited directly in
`core_components.ex`.

**Rule of thumb:** if a component is used on more than one page, retheme it
via a scoped CSS variable override, not by editing its base classes. If it's
only used on one page (like `FormCategoryComponent`, `ProfileLive.Show`,
`ProfileLive.Form`), edit it directly.

## What's deliberately unchanged

- `RecipeComponents.recipe_card` (shared with `/browse`) — the photography
  and card layout already work; not touched.
- `SelectComponent`'s DOM structure, JS hook (`Hooks.SelectComponent`), and
  event handlers — colors only, via the CSS variable seam above.
- The admin (`admin_root.heex`/`admin_live.heex`) and nutritionist
  (`nutritionist_live.heex`) layout templates — separate from the customer
  nav shell, out of scope until the admin/nutritionist rollout below happens.
- Single dark theme only — the app has no light theme today, so this system
  doesn't define one either. If a light theme is ever added, tokens should
  move to CSS custom properties redefined under `prefers-color-scheme` /
  `data-theme`, not kept as flat Tailwind color entries.

## Rollout order (suggested) — done

`/profile`, `/basket`, `/calendar`, `/create_recipe`/`/stepper`, `/browse` +
`/search`, `/home`, `/foods` + `/foods/:slug`, recipe detail (the "168
nutrients" panel now lives in `NutritionAccordion`/`AccordionComponent`, using
the `basil` token as originally intended), `/feedback`, `/upgrade`,
`/welcome`, and the login/register pages are all migrated. The nav shell
(`live.html.heex`, `main_menu.html.heex`, `mobile_menu.html.heex`) went first
so every subsequent page picked up a consistent shell immediately, instead of
last as originally suggested — this worked fine because the nav shell's own
DOM/JS wasn't touched, only its colors, and it doesn't share markup with the
admin/nutritionist layouts (they're separate `admin_root.heex`/
`admin_live.heex`/`nutritionist_live.heex` templates).

## Next candidates

1. **`/professional/**` and `/nutritionist/**`** — the only remaining
   unmigrated surfaces, internal/admin-only. Biggest remaining
   chunk (~8,500 lines). Lower visual priority since the audience is the app
   owner and nutritionist subscribers, not general customers, but worth doing
   for a consistent internal-tool experience. `Professional.IngredientLive`
   and friends still use `SelectComponent`/`SelectComponentDeep` on the old
   slate palette — safe to migrate independently of the customer app since
   they're on separate layout templates.
2. Anything under `apps/mehungry_web/lib/mehungry_web/live/professional_live/ai_bot_live/`
   in particular touches `nutrition_accordion.ex`/`accordion_component.ex`
   (now on the new palette, since recipe detail uses it) — confirm the
   AI-bot recipe review screen still reads fine now that this shared
   component changed under it (a like-for-like dark-palette swap, not
   expected to look broken, but not visually verified in this pass).

## Improvement opportunities found during this pass

Things noticed while migrating the whole app that are worth fixing but were
out of scope for a colors-only pass:

- **`get_logo` SVG has no intrinsic size, so `w-auto` doesn't compute
  correctly.** `SvgComponents.get_logo/1`
  (`apps/mehungry_web/lib/mehungry_web/components/svg_components.ex`) renders
  `<svg viewBox="0 0 450 120">` with no `width`/`height` attributes. On
  `/welcome`, `<.get_logo class="h-6 w-auto" />` measures ~774px wide in a
  real browser instead of the expected ~90px (24px height × 3.75 aspect
  ratio), squeezing the nav's "Browse Recipes" / "Sign in" links into
  overlapping two-line text at both mobile and desktop widths. Pre-existing —
  confirmed via `git diff` that this exact line was untouched by the
  migration. Fix: add explicit `width="450" height="120"` attributes to the
  `<svg>` (or set them via the `viewBox` values) so all browsers compute
  `width: auto` correctly from the intrinsic ratio.
- **No shared `<.card>`, `<.button>`, or `<.section_header>` component.**
  Every migrated page inlines the same handful of class strings
  (`bg-ink-panel border border-ink-panel2 rounded-2xl`, the paprika primary
  button, the basil numeric span) directly in `.heex`/`~H` blocks — the same
  pattern `/profile` already established. It works, but ~15 pages now repeat
  these strings verbatim. Worth extracting into `core_components.ex` once the
  admin rollout (below) is done and the full set of variants is known, so a
  future palette tweak is a one-file change instead of a repo-wide find/replace.
- **`SelectComponentDeep` lacks the CSS-variable seam `SelectComponent` has.**
  `SelectComponent` reads colors via `var(--sc-*, <old-slate-default>)`, which
  is what let every page retheme it with a scoped CSS block. `SelectComponentDeep`
  (used for the ingredient-search modal in `/create_recipe` and elsewhere)
  hardcodes `bg-slate-700`/`border-slate-600`/etc. directly, so it had to be
  rethemed via scoped utility-class overrides (`.create-recipe-page .bg-slate-700 { ... }`)
  instead — a less robust pattern that breaks if the component's own classes
  ever change. Worth giving it the same `--sc-*` variable treatment as
  `SelectComponent` for consistency.
- **Dead/commented-out markup found in several `.heex` files** —
  `recipe_browser_live/index.html.heex` (a commented-out sort-options block
  still referencing `bg-primary-500`/`bg-slate-800`), `shopping_basket_live/index.html.heex`
  (a commented-out USDA search input/loading state), and
  `calendar_live/meal_form_component.html.heex` (a commented-out "log
  consumption" block). None of it renders, so it was left alone rather than
  migrated, but it's stale enough (still on the pre-`ink`/`paprika` palette)
  that it's a candidate for deletion rather than resurrection.
- **`/stepper` routes to a module that doesn't exist.** `router.ex` has
  `live "/stepper", CreateRecipeLive.Show, :show`, but no
  `CreateRecipeLive.Show` module exists anywhere in
  `apps/mehungry_web/lib/mehungry_web/live/create_recipe_live/` — it would
  crash if visited. Unrelated to this migration; flagging since it surfaced
  during the `/create_recipe` pass.
- **Nutrient unit labels look wrong in places** — e.g. recipe ingredient
  amounts render as "1.0 Edible" or "200.0 grammar" (should presumably be a
  unit name and "grams"). This is a data/seed labeling issue in the
  `Food.Measurements`/USDA import layer, not a template bug, but it's now much
  more visible with the basil numeric styling drawing the eye to these
  values — worth a look independent of this design system work.
