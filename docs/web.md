# Web layer

All authenticated UI is Phoenix LiveView. Live sessions in `router.ex`:

| Session | `on_mount` | Routes |
|---|---|---|
| `:default` | `UserAuthLive` | `/basket`, `/calendar`, `/create_recipe`, `/upgrade`, … |
| `:default2` | `AdminAuthLive` | `/professional/**` (admin tools, AI-bot review, analytics, S3 browser) |
| `:nutritionist` | `NutritionistAuthLive` | `/nutritionist/**` |
| `:maybe` | `MaybeUserAuthLive` | `/home`, `/browse`, `/search`, `/profile`, `/foods` |
| `:default3` | none | `/welcome` (landing) |

Dead scaffold routes (`PostLive`, `CommentLive`, `CommentAnswerLive`,
`SurveyLive` — modules that never existed) were removed in the 2026-07
refactor; don't re-add routes without a backing module.

## Conventions

- Live Components: clear division between View (render) and Update code;
  define view functions in invocation order starting with `render`.
- Modals: three patterns coexist; **prefer the `core_components.ex` modal**
  for new code.
- Shared formatting helpers: `MehungryWeb.FormatHelpers` (`month_name/1`,
  `truncate/2`) — import with an explicit `only:` list. Add helpers here only
  when duplicated copies are identical; intentionally divergent local
  variants (per-dashboard `format_dt`, `status_label` wordings, badge
  classes, the locale-aware `CalendarLive.Calendar.Locale.month_name/2`)
  stay local.
- Presence: `use MehungryWeb.Presence, :user_tracking` to opt in.
- Frontend: Tailwind + DaisyUI, Alpine.js, Vega-Lite hooks; jQuery +
  Select2/Selectize are legacy and being phased out.

## Known debt (flagged, deliberately not fixed in the refactor)

These are behavior-sensitive and need product/owner decisions:

- `landing_live.ex` (~1200 lines) builds Ecto queries and calls `Repo.all`
  directly; should move behind a context function.
- `profile_live/index.ex:~68` seeds `FoodRestrictionType` rows inside
  `mount/3` — data seeding does not belong in a LiveView.
- `calendar_live/index.ex` calls `Repo.preload` directly.
- Telemetry dashboard pages (`errors_page`, `query_times_page`,
  `endpoint_times_page`, `query_timeline_page`) query `Mehungry.Telemetry.*`
  with raw Ecto — acceptable for admin tooling, but context functions would
  be cleaner.
- `core_components.ex` (~1600 lines) is a grab-bag; split when touched.
- The social posting user flow duplicates platform dispatch — see
  `docs/social_publishing.md`.
- `MehungryWeb.ImageProcessing` stays in web because it builds URLs from
  `MehungryWeb.Endpoint`; it is presentation-adjacent.
