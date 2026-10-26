# Google Meet for Appointments — Assessment & Minimal Build

**Status:** minimal slice built (manual link). Automatic Meet-link generation is
**designed here** as the next increment.

Assesses giving each accepted appointment a video-call link so client and nutritionist can
meet online.

## 1. What's built now (minimal slice)

The `professional_appointments.meeting_url` column + UI:

- When a nutritionist **accepts** a request (`/nutritionist/appointments`, the pending-requests
  panel), they can paste a video-call link (any URL — a Google Meet, Zoom, etc.).
- The link is stored on the appointment and surfaced in:
  - the acceptance email (`UserNotifier.deliver_appointment_accepted/3`) — as the primary CTA
    ("Join the video call"), and
  - the attached `.ics` invite (`Mehungry.Professionals.ICS`) — as `LOCATION`/`URL`, so it
    rides into the client's Google/Apple/Outlook calendar.

This requires **no Google integration** and works today for any provider.

## 2. Next increment — auto-generate a Meet link

To create the Meet link automatically (no copy-paste), use the **Google Calendar API**, not a
standalone "Meet API" (there is no public API to mint a bare Meet link — links are created as a
side effect of a Calendar event).

- **Call:** `events.insert` on the nutritionist's calendar with
  `conferenceData.createRequest.conferenceSolutionKey.type = "hangoutsMeet"` and a unique
  `requestId`; pass `conferenceDataVersion=1`. The response's
  `conferenceData.entryPoints[].uri` is the `https://meet.google.com/...` link. Store it in
  `meeting_url`.
- **Bonus:** the same event, created with both parties as `attendees`, gives real two-way
  calendar sync + Google's own reminders — arguably better than our `.ics` attachment.

### OAuth / auth (the real work)

- **Scope:** `https://www.googleapis.com/auth/calendar.events` — a **write** scope, far
  broader than the login scope. This is per-**nutritionist** consent (their calendar hosts the
  event), so it cannot reuse the existing Ueberauth **login** flow.
- **Distinct from current Google login:** `ueberauth_google` is configured for sign-in only
  and does not persist a refresh token or request calendar scope. We'd add a **separate**
  OAuth connection ("Connect Google Calendar" on `/nutritionist/profile`), request
  `access_type=offline` + `prompt=consent` to get a **refresh token**, and store the
  encrypted token per nutritionist (a new `professional_google_tokens` table or columns).
- **Token lifecycle:** access tokens last ~1h; use the refresh token to mint new ones
  (mirror the pattern of `Social.Instagram.Token` refresh + the daily
  `InstagramTokenRefreshWorker`). Handle revocation → fall back to the manual `meeting_url`.
- **Verification/branding:** the Google OAuth consent screen needs the calendar scope; a
  sensitive-scope app may need Google verification before external users can consent.

## 3. Effort & risk

- **Manual link (done):** ~0 extra — reuses `meeting_url`. No external dependency.
- **Auto-generate increment:** ~2–3 days: second Google OAuth flow, encrypted per-nutritionist
  token storage + refresh worker, `events.insert` client, wiring into `accept_appointment/1`,
  and graceful fallback to manual on any Google error. Medium risk — mostly OAuth consent /
  token-refresh edge cases and Google app-verification lead time.

## 4. Recommendation

Ship the **manual link** now (done). Build **auto-generation** only if nutritionists ask for
it — and when we do, prefer the full `events.insert` + attendees approach so we get Meet link
**and** native two-way calendar sync in one call, rather than bolting a link onto our own
`.ics`.
