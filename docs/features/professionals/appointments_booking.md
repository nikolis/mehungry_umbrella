# Appointment Booking (request → accept → invite)

How a visitor books a nutritionist, how availability is computed, and how acceptance sends a
calendar invite. Profile/discovery is in `professional_profiles.md`.

## Data model

- **`ProfessionalAvailability`** (`professional_availabilities`) — recurring **weekly** windows:
  `day_of_week` (0 = Sunday … 6 = Saturday), `start_time`, `end_time`. The nutritionist edits
  these as a Mon→Sun grid on `/nutritionist/profile`. `Professionals.replace_availabilities/2`
  swaps the whole grid in one transaction (one window per day from the editor; the slot engine
  supports multiple).
- **`Appointment`** (`professional_appointments`) gained a `status`
  (`requested | accepted | declined | cancelled`, default `requested`) and a `meeting_url`.
  A booking sets `client_id` = the logged-in visitor, `status: "requested"`. No
  `TutorClientAssignment` is required — anyone can request; accepting doesn't make them a
  managed client.

## Slot engine — `Professionals.available_slots/3`

For a professional + date range: slices each weekly window into
`profile.appointment_slot_minutes` slots, drops slots in the past, slots that **overlap** a
`requested`/`accepted` appointment's `[scheduled_at, ends_at)` interval, **and slots overlapping a
cached Google Calendar busy interval** (`professional_calendar_busy`, see Google Calendar sync
below) — returns sorted `NaiveDateTime`s (UTC, second precision). Both booked appointments and
busy times are tested with the same interval-overlap predicate (`slot_overlaps?/3`), so an
off-grid or differently-sized appointment (e.g. a 09:30–10:30 slot created in the nutritionist
calendar) blocks **every** grid slot it spans — not only one whose start matches exactly (a
missing `ends_at` is coalesced to one slot after the start). `request_appointment/4` re-checks the
slot is open (`slot_open?/2`) before inserting, returning `{:error, :slot_unavailable}` on a race.

## Nutritionist calendar view — `/nutritionist/appointments`

The nutritionist calendar (`MehungryWeb.NutritionistLive.AppointmentCalendar`) is a month grid.
**Clicking a day opens a day-agenda modal** — a vertical 06:00–22:00 hourly breakdown of that
day's appointments as time-positioned blocks (color-coded by status), with the nutritionist's
weekly availability window shaded and, when Google Calendar is connected, their imported busy
intervals overlaid. Clicking an appointment block opens the edit form; clicking an empty hour (or
the modal's **"+ New"**) opens the create form pre-filled for that date/hour. The month-cell
chips still open edit directly.

**Log measurement from the meeting.** The appointment edit modal has a **"Log measurement"** button
(shown only when the appointment has an internal `client_id` — **hidden for external clients**, who
have no platform user and thus no clinical file). It resolves the appointment's client `User` to the
nutritionist's `ProfessionalClient` via `Professionals.ensure_client_record/2` (lazy-creating the
file if none exists) and opens a measurement form (weight, body fat %, waist, muscle mass). On save
it writes a `ConsultationNote` pre-linked to the appointment (`appointment_id`) and dated to the
appointment; BMI/BMR are auto-filled from the client's latest intake. **One note per meeting:** if
progress was already logged for that appointment the button re-opens the form **pre-filled** with the
existing note, and saving **updates** it rather than inserting a second row
(`Professionals.upsert_consultation_note_for_appointment/1`) — and if stale duplicates linger from
before this rule, the most recent is updated and the rest are deleted in the same transaction, so
exactly one note survives. These measurements feed the
client-file **Progress trend** chart and the client's own **My progress** profile chart — see
[`client_records.md`](client_records.md) §Progress tracking.

## Flow

1. **Request** — logged-in visitor picks a **service** (the booking modal lists the active
   `ProfessionalService`s — free intro + paid session/package, with prices), then an open slot. The
   booking wizard (pick day → time → service → confirm) is the shared
   **`MehungryWeb.AppointmentBookingComponent`** LiveComponent, reused on both the public profile
   `/nutritionists/:slug` (`PublicNutritionistLive.Show`, `variant: :card`) **and** the client's
   "My nutritionist" hub for an already-connected client (`MyNutritionistLive.Index`,
   `variant: :button`) — so the slot engine, Stripe-authorise redirect, and "requested" mailer live
   in exactly one place. The component owns its own slot/service loading and all booking events
   (`phx-target`'d to itself), surfaces slot-contention errors inside the modal, and notifies its
   parent with `{:appointment_booked, appt}` so the client's appointment list refreshes. Logged-out
   visitors are redirected to log in. On success: an `AppointmentMailerWorker` "requested" email
   notifies the nutritionist.
   The visitor sees "awaiting confirmation" — **nothing is confirmed yet**. For a **paid** service
   (when the consultation-payments flag is on and the nutritionist is Stripe-Connect-onboarded) the
   request instead opens a manual-capture Stripe Checkout and redirects the client to **authorize**
   (hold) their card; the hold is only captured on acceptance. See the payments docs below.
2. **Accept / decline** — nutritionist sees pending requests on `/nutritionist/appointments`
   (amber panel + amber calendar chips). Accept optionally attaches a `meeting_url`
   (`Professionals.accept_appointment/2`) and, for paid bookings, **captures** the card hold first;
   decline (`decline_appointment/1`) **releases** the hold. A `mark_no_show/1` action retains a
   captured payment in full. Both enqueue an `AppointmentMailerWorker` email.
3. **Cancellation (two surfaces, two policies):**
   - **Client** cancels from the **"My nutritionist" hub** (`/my-nutritionist`,
     `MyNutritionistLive.Index` — see below), in its secondary appointments section —
     `cancel_appointment/1` applies the **tiered** refund (≥24h → 100%, 4–24h → 50%, <4h → 0%);
     the confirm dialog previews the amount via `client_cancellation_refund_cents/1`.
   - **Nutritionist** cancels an **accepted** appointment from the calendar edit modal
     ("Cancel & refund") — `cancel_appointment_by_professional/1` **always fully refunds** the
     client (an uncaptured hold is released; a captured payment is fully reversed), since the
     client is never penalised for the nutritionist calling it off.
3. **Invite** — the acceptance email (`UserNotifier.deliver_appointment_accepted/4`) attaches an
   `.ics` built by `Mehungry.Professionals.ICS` (VCALENDAR/VEVENT, UTC, `meeting_url` as
   `LOCATION`/`URL`) so the client can add it to any calendar.

## Client hub — "My nutritionist" (`MyNutritionistLive.Index`)

The consumer-facing entry point for the client↔nutritionist relationship, at **`/my-nutritionist`**
(menu label "My nutritionist", icon `hero-user-circle`; `/appointments` is kept as a backwards-compatible
alias to the same LiveView). It is **not** primarily an appointment list — appointments are a secondary
section. Two states, driven by `Professionals.get_assignment_for_client/1` (one connected nutritionist max):

- **Connected** — leads with a **preview of the connected nutritionist's public profile** (resolved via
  `get_professional_profile/1`, since `get_assignment_for_client/1` preloads only the `:professional`
  `User`, not the `ProfessionalProfile`). Rendered with the shared `nutritionist_card/1` component
  (`variant: :preview`, in `core_components`) with CTAs: **Book an appointment** (the shared
  `AppointmentBookingComponent`, `variant: :button` — a connected client books right here without
  leaving the hub), **View full profile** (`/nutritionists/:slug`), **Message** (`/messages`), an
  anchor to the appointments section, and **Disconnect** (`unlink_nutritionist` →
  `Professionals.unassign_nutritionist/1`, confirm-gated — a client can end the link themselves; the
  hub then falls back to the unconnected empty state).
- **Unconnected** — a plain **empty state**: a people icon + "You're not connected to a nutritionist
  yet." + a link to the full `/nutritionists` directory. This hub deliberately shows **no inline
  nutritionist search or list** — discovery happens in the directory, not here.

**Pending invitations** from nutritionists surface as a top banner (unconnected state) with inline
accept/decline (handlers lifted verbatim from `NutritionistLive.UserInvitations`, backed by
`accept_invitation/2` / `decline_invitation/2`; `unassign_nutritionist/1` for unlink). The appointments
section is wrapped in a **max-height scroll**, preserves the tiered-refund cancel flow, and renders times
in the professional's timezone (§ below). Paid bookings started from this hub return via
`/my-nutritionist?booking=success|cancelled`, flashed by its `handle_params`.

## Email delivery

`Mehungry.ObanWorkers.AppointmentMailerWorker` runs on the **`:mailers`** Oban queue (this is
the first worker to use that provisioned queue). The **web caller** supplies display strings
(`professional_name`, `client_name`) and the CTA URL (built from verified routes) as job args,
so the core app never needs web routing. Emails reuse `UserNotifier`'s branded `html_layout/7`.
Kinds: `requested`/`accepted`/`declined`, plus **`cancelled_by_client`** (notifies the
nutritionist the slot is free) and **`cancelled_by_professional`** (notifies the client, with a
full-refund note). Both cancel handlers enqueue the matching email.

**Localization** — each email is sent in the **recipient's** language (their
`language_preference`): the nutritionist for `requested`/`cancelled_by_client`, the client for
`accepted`/`declined`/`cancelled_by_professional`. The worker resolves the locale and passes it
to each `UserNotifier.deliver_appointment_*/4`; the core app has no Gettext backend (it can't
depend on the web app), so these emails carry explicit EN/EL variants via a `tr/3` helper — the
subject, body, the `.ics` SUMMARY (`Consultation with …` / `Συνεδρία με …`), and the date (Greek
month/day names via `Calendar.strftime` name options) all switch together. See
`docs/implementation/localization.md`.

## Google Calendar two-way sync (optional, per-nutritionist)

A nutritionist can **connect their Google Calendar** from `/nutritionist/appointments` (the
"Connect Google Calendar" banner). This is a **separate OAuth flow** from Google login
(`MehungryWeb.GoogleCalendarOAuthController` → `/nutritionist/google-calendar/connect` marks the
session and redirects into the Ueberauth Google request phase with the `calendar.events` +
`calendar.readonly` scopes, `access_type=offline`, `prompt=consent`; `AuthController`'s `:google`
callback branches on the marker and persists the tokens via
`Professionals.connect_google_calendar/2` into `professional_google_accounts`,
`Mehungry.Professionals.GoogleAccount`). Disconnect (`DELETE /nutritionist/google-calendar/disconnect`)
drops the tokens + cached busy rows.

- **Push (app → Google):** on accept/reschedule the context enqueues
  `Mehungry.ObanWorkers.AppointmentCalendarSyncWorker` (`:mailers` queue, off the request cycle) →
  `Mehungry.Professionals.GoogleCalendar.sync_appointment/1`, which creates (or patches) an event
  on the nutritionist's calendar, **minting a Google Meet link** via
  `conferenceData.createRequest` and adding the client as an attendee, then stores the event id
  (`professional_appointments.google_event_id`) + Meet URL (`meeting_url`). Decline/cancel/delete
  enqueue a `:delete`. **Any Google error is best-effort** — the appointment keeps the manual
  `meeting_url` fallback and the user action never fails. A manually pasted `meeting_url` is kept
  as the event `LOCATION` instead of minting a Meet link.
- **Import (Google → app):** `Mehungry.ObanWorkers.GoogleCalendarBusyImportWorker` (cron, every
  20 min; also enqueued right after connect) reads each connected nutritionist's free/busy for the
  next 8 weeks and **replaces** their `professional_calendar_busy` cache
  (`Mehungry.Professionals.CalendarBusy`). The slot engine subtracts these, so the public booking
  page respects the nutritionist's personal calendar **without a live Google call** (reads the
  local cache only).
- The HTTP client (`Mehungry.Professionals.GoogleCalendar.Client`, behind `ClientBehaviour`) is
  swapped in tests via the `:google_calendar_client` config seam. Access tokens are refreshed
  on demand (refresh token → Google token endpoint) before each call.

> **Token storage:** OAuth tokens are stored in plaintext columns, matching the app's existing
> provider-token practice (`users.instagram_token` etc.); encrypting them is a tracked follow-up.
> The `calendar.events` sensitive scope requires Google app **verification** before external
> nutritionists can consent — the manual `meeting_url` is the fallback until then.

## Notes / future

- Times are handled in UTC end-to-end; per-nutritionist timezone display uses the profile
  `timezone`. The client "My nutritionist" hub (`MyNutritionistLive.Index`) renders each
  appointment in its **professional's** timezone with the zone abbreviation (e.g. `14:00 EET`)
  via `Mehungry.Time`, so a client in another zone isn't misled. (Not yet applied to the
  public booking calendar — future polish.)
- Paid bookings are built (see `docs/implementation/professionals/payments/…`); auto-generated
  Meet links now ship via the Google Calendar sync above (see
  `docs/implementation/professionals/integrations/google_meet.md`).
