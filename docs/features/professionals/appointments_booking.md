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
`profile.appointment_slot_minutes` slots, drops slots in the past and slots already taken by a
`requested`/`accepted` appointment, returns sorted `NaiveDateTime`s (UTC, second precision).
`request_appointment/4` re-checks the slot is open (`slot_open?/2`) before inserting, returning
`{:error, :slot_unavailable}` on a race.

## Flow

1. **Request** — logged-in visitor picks an open slot on `/nutritionists/:slug`
   (`PublicNutritionistLive.Show`). Logged-out visitors are redirected to log in. On success:
   an `AppointmentMailerWorker` "requested" email notifies the nutritionist. The visitor sees
   "awaiting confirmation" — **nothing is confirmed yet**.
2. **Accept / decline** — nutritionist sees pending requests on `/nutritionist/appointments`
   (amber panel + amber calendar chips). Accept optionally attaches a `meeting_url`
   (`Professionals.accept_appointment/2`); decline (`decline_appointment/1`) notifies the
   client. Both enqueue an `AppointmentMailerWorker` email.
3. **Invite** — the acceptance email (`UserNotifier.deliver_appointment_accepted/3`) attaches an
   `.ics` built by `Mehungry.Professionals.ICS` (VCALENDAR/VEVENT, UTC, `meeting_url` as
   `LOCATION`/`URL`) so the client can add it to any calendar.

## Email delivery

`Mehungry.ObanWorkers.AppointmentMailerWorker` runs on the **`:mailers`** Oban queue (this is
the first worker to use that provisioned queue). The **web caller** supplies display strings
(`professional_name`, `client_name`) and the CTA URL (built from verified routes) as job args,
so the core app never needs web routing. Emails reuse `UserNotifier`'s branded `html_layout/7`.

## Notes / future

- Times are handled in UTC end-to-end; per-nutritionist timezone display uses the profile
  `timezone` (not yet applied to the public calendar — future polish).
- Paid bookings and auto-generated Meet links are the next increments — see
  `docs/payments/nutritionist_payments_stripe_connect.md` and `docs/integrations/google_meet.md`.
