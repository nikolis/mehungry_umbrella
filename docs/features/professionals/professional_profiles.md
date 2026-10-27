# Professional (Nutritionist) Public Profiles

How a nutritionist (`pro` tier) builds a rich, publicly discoverable profile, and how the
public directory + SEO surface works. Booking is documented separately in
`appointments_booking.md`.

## The profile (`Mehungry.Professionals.ProfessionalProfile`)

One row per user (`unique_index(:user_id)`). Beyond the original `specialization` + `bio`
(now the *short bio*), the schema carries public-facing detail and contact fields:

- **Identity:** `display_name`, `slug` (unique, URL key), `photo_url`, `is_public`.
- **Details:** `education`, `scientific_contributions`, `professional_achievements`.
- **Contact/location:** `city`, `region`, `office_address`, `phone`, `contact_email`,
  `website_url`, `timezone`.
- **Scheduling:** `appointment_slot_minutes` (see booking doc).
- **Payments:** `consultation_fee_cents`, `stripe_connect_account_id`,
  `stripe_charges_enabled` (see `docs/payments/nutritionist_payments_stripe_connect.md`).

**Slug** is generated from `display_name` by `ProfessionalProfile.slugify/1` and disambiguated
against existing rows by `Professionals` (`ensure_unique_slug/2` → `-1`, `-2`…). It is stable
once set.

**Publishing** is gated: `is_public` requires `display_name`, `city` and `bio`
(`validate_public_completeness/1`) so a live page always renders well and ranks locally.

Two changesets: `changeset/2` (user-editable copy + slug + publish gate) and `stripe_changeset/2`
(Connect fields only — webhooks/onboarding never touch profile copy).

## Editing — nutritionist workspace

`/nutritionist/profile` → `MehungryWeb.NutritionistLive.ProfileEdit` (in the authenticated,
subscription-gated `:nutritionist` live_session). One form covers all fields, the publish
toggle, the weekly availability grid, photo upload, and Stripe payout onboarding. Photo uploads
reuse the external-S3 presign path (`MehungryWeb.SimpleS3Upload.meta_for/3`, prefix
`profile_photos/`). The old inline profile form on the Dashboard was removed; the Dashboard now
links here.

## Public directory + profile (SEO)

Both live in the public, localized `:maybe` live_session:

- `/nutritionists` → `PublicNutritionistLive.Index` — lists published profiles; filters by
  **city** and free text. Filtered titles ("Nutritionists in Rethymno") target local intent.
  Emits `ItemList` JSON-LD.
- `/nutritionists/:slug` → `PublicNutritionistLive.Show` — full profile + booking sidebar.
  Emits **`LocalBusiness` + `Person` JSON-LD** (address/`areaServed` = city, telephone,
  specialty) for local ranking ("nutritionist Rethymno").

**Crawler correctness (`docs/seo.md`):** the profile body is rendered **synchronously** in
`mount` (no `assign_async` for profile data), so the disconnected dead render Googlebot indexes
has the real bio/city/JSON-LD. Meta comes from plain-string `:page_title` + `:page_description`
+ explicit `:canonical_path` (the request path — *not* the recipe `page_seo_data` map, which
hardcodes `/browse/:id`), plus the generic `:structured_data` `@graph` slot.

**Sitemap/robots:** `SitemapController` adds `/nutritionists` and one localized entry per
published profile. `robots.txt` allows `/nutritionists` and disallows the private
`/nutritionist/` workspace. (Note the singular/plural distinction — do **not** add
`/nutritionist` to the head's `noindex_prefixes`, as it would also match `/nutritionists`.)

### Marketing landing is nutritionist-led

The public marketing landing (`LandingLive`, `/welcome`, `:default3`) is **positioned for
professional nutritionists first** (2026-10-26 repositioning — automated meal planning for the
`m3hungry_plus`/consumer tier is the *second* act, not the lead). The hero copy sells the
practice — *"Grow your nutrition practice. Keep it 100% yours."* — with the "**still 100% you**"
spine (AI drafts; the nutritionist reviews/adjusts/approves) and a secondary CTA into
`/nutritionists`.

**Body re-sequenced to lead with the moat (2026-10-27).** The page previously sold the consumer
food tracker below the hero; it now reads as *one professional workspace*, in this order:
**(1) hero**, **(2) the literature assistant** — the signature section and headline
differentiator (*"The evidence, graded. The conclusion, yours."*): a **search PubMed → read
full text with claims highlighted → save as your own notes → resurfaces on the client with that
condition** flow, beside an **evidence ladder rendered from the real grading scheme**
(`Mehungry.Literature.ResearchType.buckets/0` — not invented copy). Framed strictly as a
**tool for the professional, never an oracle** — we surface graded, provenance-backed evidence;
the nutritionist reaches the conclusion (mirrors the `Health` YMYL boundary). **(3) the
point-of-care loop** (*"Your notes find your client"* — the `professional_client_conditions`
link surfacing saved notes, plus auto BMI/BMR/TDEE intake), **(4) the complete practice** — a
capability grid making completeness legible (profile+SEO · booking · payouts · client records ·
literature assistant · articles), **(5) AI drafts-you-approve**, **(6) USDA/168-nutrient depth
demoted to a credibility proof-point** (with the meal-calendar + nutrition-chart demo folded in),
**(7) the consumer ring kept but demoted** (recipe discovery + social — "the platform your
clients use"), then pricing + CTA.

**Honest, verifiable counts only.** `mount/3` loads real aggregates:
`Food.count_ingredients/0` (hero "foods" figure, replacing a hardcoded `10,000+`) and the
literature-assistant proof numbers `Literature.count_analyzed_studies/0` +
`count_conditions_with_research/0` (both single-aggregate reads in
`Literature.StudyAnalyses`; **omitted rather than shown as "0"** on an empty research DB). The
"168 nutrients" figure stays a labeled USDA domain claim.

The hero **features a real published profile** when one exists:
`Professionals.list_public_professionals() |> List.first()` feeds a profile card (real
`display_name`/`specialization`/`city`/`photo_url`/`slug`). When **no** profile is public it
falls back to an honest "Your name here" preview — it never invents a person. Per the page's
no-fake-stats rule the practice-dashboard figures beside it are an `aria-hidden`, illustrative
preview captioned *"Example dashboard"* (not live counts). `/foods` stays as the public
consumer "proof engine" behind the pitch. See `MEMORY` → *Nutritionist Repositioning* for the
rest of the ranked roadmap (role-branched entry screen, pricing flip).

## Context API (`Mehungry.Professionals`)

`list_public_professionals/1` (filters), `get_public_professional_by_slug/1`,
`list_professional_cities/0`, `update_professional_stripe/2`,
`get_profile_by_stripe_account/1`, `set_stripe_charges_enabled/2`.
