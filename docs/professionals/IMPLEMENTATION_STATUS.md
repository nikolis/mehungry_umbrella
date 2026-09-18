# Nutritionist Public Profiles & Booking — Implementation Status

**Branch:** `new_professional_nutritionist_features`
**Last updated:** 2026-09-08

Status snapshot of the professional-nutritionist feature set: public discovery + booking +
payments/Meet, scientific **Articles**, and **client records / dietary history**. For the
how-it-works reference see the sibling docs linked below; this file is the delivery record (what's
done, what's stubbed, what's next).

## Original requirements → status

| # | Requirement | Status |
|---|---|---|
| 1 | Pro subscribers can create a full professional profile | ✅ Done |
| 2 | Details: bio, education, scientific contributions, achievements, city, phone, email… | ✅ Done |
| 3 | Ability to make the profile public | ✅ Done (gated on name+city+bio) |
| 4 | Public profile is SEO-eligible; rank for "nutritionist, Rethymno" | ✅ Done (LocalBusiness JSON-LD, directory, sitemap) |
| 5 | Calendar booking → nutritionist accepts → email + calendar invite | ✅ Done (weekly availability, `.ics` invite) |
| 6 | Assess + document Stripe user→nutritionist payments | ✅ Doc + minimal build (Connect onboarding) |
| 7 | Assess + document Google Meet integration | ✅ Doc + minimal build (manual link) |
| 8 | Author public, evidence-based **scientific articles** | ✅ Done (per-paragraph images + PubMed/species/compound/disease refs, published SEO pages) |
| 9 | Keep **client records / dietary history** (intake + consultation notes) | ✅ Done (CSV import **and** manual authoring; external or platform-user-linked) |

## Reference docs

- `docs/professionals/professional_profiles.md` — profile schema, editor, public directory, SEO
- `docs/professionals/appointments_booking.md` — availability, request→accept flow, ICS/email
- `docs/professionals/articles.md` — article model, editor, public rendering + JSON-LD
- `docs/professionals/client_records.md` — client file, CSV import + manual editor, associations
- `docs/payments/nutritionist_payments_stripe_connect.md` — Stripe Connect assessment + minimal build
- `docs/integrations/google_meet.md` — Google Meet assessment + minimal build
- `docs/seo.md` — has a new "Worked example: nutritionist profiles (local SEO)" section

## Data model

**Migrations** (`apps/mehungry/priv/repo/migrations/`):
- `20260902000001_extend_professional_profiles.exs` — public/detail/contact/payment fields + `slug` (unique) + `is_public`; indexes on `slug`, `city`, `[is_public, city]`
- `20260902000002_create_professional_availabilities.exs` — weekly recurring windows
- `20260902000003_add_status_and_meeting_url_to_professional_appointments.exs` — `status` + `meeting_url`
- `20260903000001..003` — `professional_articles`, `professional_article_paragraphs`, `professional_article_references`
- `20260904000001..003` — `professional_clients`, `client_intakes`, `consultation_notes`

**Schemas** (`apps/mehungry/lib/mehungry/professionals/`):
- `professional_profile.ex` — `changeset/2` (editable copy + slug gen + publish gate), `stripe_changeset/2`, `slugify/1`
- `professional_availability.ex` — new; `day_of_week` 0=Sun..6=Sat + start/end time
- `appointment.ex` — added `status` (`requested|accepted|declined|cancelled`), `meeting_url`, `status_changeset/2`
- `article.ex` / `article_paragraph.ex` / `article_reference.ex` — public scientific articles (draft→published, per-paragraph images + polymorphic-lite references)
- `professional_client.ex` / `client_intake.ex` / `consultation_note.ex` — client file (PII + optional `user_id`), typed intake + JSONB `details`, per-visit notes; `dietary_history/{csv_parser,importer,fields}.ex`

## Backend

- **`professionals.ex`** (context): public discovery (`list_public_professionals/1`,
  `get_public_professional_by_slug/1`, `list_professional_cities/0`), slug disambiguation,
  availability (`list_availabilities/1`, `replace_availabilities/2`, `available_slots/3`),
  booking (`request_appointment/4`, `accept_appointment/2`, `decline_appointment/1`,
  `cancel_appointment/1`, `list_pending_requests/1`), Stripe helpers
  (`update_professional_stripe/2`, `get_profile_by_stripe_account/1`,
  `set_stripe_charges_enabled/2`).
- **`professionals/ics.ex`** — new RFC-5545 VCALENDAR/VEVENT builder.
- **`accounts/user_notifier.ex`** — `deliver_appointment_{requested,accepted,declined}`
  (accepted attaches the `.ics` as `text/calendar`), reusing the branded `html_layout/7`.
- **`oban_workers/appointment_mailer_worker.ex`** — new, on the `:mailers` queue (its first
  user). Web callers pass display names + CTA url as job args.
- **`billing/stripe_handler.ex`** — Connect: `create_connect_account/1`,
  `create_account_link/2`, `get_connect_account/1`, `account.updated` webhook + a GET helper.

## Web

- **Public** (`live_session :maybe`, localized): `PublicNutritionistLive.Index`
  (`/nutritionists`) + `PublicNutritionistLive.Show` (`/nutritionists/:slug`). SEO via
  plain-string title + `canonical_path` + `LocalBusiness`/`Person` (Show) / `ItemList` (Index)
  JSON-LD; profile body rendered synchronously for the crawler dead render.
- **Workspace** (`live_session :nutritionist`): `NutritionistLive.ProfileEdit`
  (`/nutritionist/profile`) — all fields, S3 photo upload, publish toggle, weekly availability
  grid, Stripe onboarding. `AppointmentCalendar` gained a pending-requests panel + Accept/Decline
  + `meeting_url` + status-colored chips. Dashboard now links to the editor.
- **Infra**: routes in `router.ex`; sitemap adds `/nutritionists` + per-profile entries;
  `robots.txt` allows `/nutritionists`, disallows `/nutritionist/`; `SimpleS3Upload.meta_for/3`
  (prefix `profile_photos/`); "My Profile" sidebar link.
- **Articles** (`live_session :nutritionist` + public `:maybe`): `ArticleEditor`
  (`/nutritionist/articles/:id/edit`, incremental persistence) + public
  `PublicNutritionistLive.Article` (`/nutritionists/:slug/articles/:article_slug`, dead-render body
  + `Article` JSON-LD + numbered bibliography). See `docs/professionals/articles.md`.
- **Client records** (`live_session :nutritionist`): `Records` (`/nutritionist/records`, roster +
  CSV import), `ClientRecord` (read-only view), and `ClientRecordEditor`
  (`/nutritionist/records/new` + `/records/:id/edit`) — manual authoring at full parity with
  import, with external-vs-platform-user association. See `docs/professionals/client_records.md`.

## Verification

- **Unit:** `apps/mehungry/test/mehungry/professionals_test.exs` — profile/booking (slug
  uniqueness, publish gating, `available_slots` open-minus-booked, request rejects taken/out-of-window
  slots, accept/decline transitions, public filtering) + article CRUD/slug/reference-FK.
- **Web:** `.../nutritionist_live/article_test.exs` (author → publish → public dead render + JSON-LD;
  draft redirect) and `.../nutritionist_live/client_record_editor_test.exs` (external create → intake
  typed/detail/recall → note → read-only render; platform-user link via dropdown; failed email lookup
  flash; ownership redirect). Professionals + nutritionist_live suites green (17 tests).
- **Full suite:** green except the pre-existing Wallaby browser feature tests that need
  `chromedriver` (not installed) — unrelated to this work.
- **Live app (curl against dev):** `/nutritionists` and `/nutritionists/:slug` return 200 with
  correct `<title>`, locale `canonical`, and valid `LocalBusiness`+`Person`+`PostalAddress`
  JSON-LD in the dead render; city filter works; 120 booking slots rendered; sitemap + robots
  correct.
- **Email/ICS:** exercising accept → produced a valid VCALENDAR with the Meet link and an email
  with a `text/calendar` attachment (local mailer adapter).
- Demo data seeded in the dev DB: user `nutri_demo@example.com`, public profile slug
  `maria-papadaki` (Rethymno), plus `client_demo@example.com`.

## Known gaps / next increments

- **Paid bookings** — `consultation_fee_cents` is captured but unused; charging (manual-capture
  PaymentIntent on request → capture on accept) is designed in the Stripe doc, not built. The
  profile editor's fee input is labelled EUR but stores the raw number as cents — wire this up
  when charging lands.
- **Auto Google Meet links** — currently manual paste; Calendar-API `events.insert` +
  per-nutritionist OAuth is designed in the Meet doc, not built.
- **Timezone display** — appointments are UTC end-to-end; the profile `timezone` isn't yet
  applied to the public booking calendar.
- **Availability editor** supports one window per day (the slot engine supports several).
- **Articles v1** — single-language, plain paragraph body (no rich text / inline autolinking),
  no comments/reactions (deliberate deferrals — see `docs/professionals/articles.md`).
- **Client records** — the manual intake stores every questionnaire field it renders (empty keys
  included); no BMI/BMR auto-calculation from anthropometrics yet, and no link back from a
  `ProfessionalClient` to the booking/appointment timeline.
