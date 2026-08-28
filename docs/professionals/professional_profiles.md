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

## Context API (`Mehungry.Professionals`)

`list_public_professionals/1` (filters), `get_public_professional_by_slug/1`,
`list_professional_cities/0`, `update_professional_stripe/2`,
`get_profile_by_stripe_account/1`, `set_stripe_charges_enabled/2`.
