# Social media publishing

## Disabling platforms

`Mehungry.Social` holds global per-platform kill switches:

```elixir
config :mehungry, :social_platforms,
  facebook: true,
  instagram: false,
  pinterest: false
```

A platform absent from the config defaults to **enabled**. `Mehungry.Social.platform_enabled?/1`
is the single check used in three places:

- `Social.Publisher.post_platform/3` — a disabled platform is `:skipped`, no post is
  attempted (regardless of the per-job `platforms` allow-list).
- The user-flow share entry points (`post_card.html.heex`, `core_components.ex`
  share menus) are hidden with `:if`.
- `HomeLive.Index` `:share_social_media` action refuses the route for a disabled
  platform (guards against a direct URL).

Instagram and Pinterest are **currently disabled** (platform-app issues). Flip the
flag to re-enable, or override at runtime with `SOCIAL_PLATFORMS_DISABLED`
(comma-separated, e.g. `instagram,pinterest`) — see `runtime.exs`.

## Seam

`Mehungry.Social.PublisherBehaviour` defines `publish_recipe/5`.
The canonical implementation is **`Mehungry.Social.Publisher`** (core).
`RecipePublishWorker` resolves the module at runtime:

```elixir
Application.get_env(:mehungry, :social_media_publisher, Mehungry.Social.Publisher)
```

- `config/test.exs` sets the key to `Mehungry.Social.PublisherStub`.
- `Mehungry.SocialMediaPublisher` (old core name) and
  `MehungryWeb.SocialMediaPublisher` are deprecated defdelegate shims kept in
  case an environment config still names them.

## Platform clients (all in core, under `Mehungry.Social.*`)

| Client | Transport | Notes |
|---|---|---|
| `Mehungry.Social.Instagram` (+ `Instagram.Client` behind `Instagram.ClientBehaviour`) | HTTPoison | Long-lived token lifecycle in `Instagram.Token`; captions capped at 2200 chars by `Instagram.Caption`; stubbed in tests via `:instagram_client` |
| `Mehungry.Social.Facebook` | HTTPoison | Page posts via stored page tokens on `facebook_token`; returns `{:ok, body} \| {:error, {:http_error \| :transport_error, ...}}` |
| `Mehungry.Social.Pinterest` (+ token lifecycle in `Pinterest.Token`) | HTTPoison (stubbed in tests via `:pinterest_http_client`) | Host comes from `:pinterest_api_base`, set in `runtime.exs` from `PINTEREST_ENV` (`live` → real API, anything else/unset → sandbox). Tokens are not interchangeable between environments — reconnect accounts after switching; the ueberauth strategy and token exchange read the same key. Access tokens (~30 days) are auto-refreshed from the stored refresh token (see below). Builds pin links via the `:endpoint_module` runtime seam |

OAuth strategies for connecting accounts stay in the web app
(`mehungry_web/ueberauth/strategy/{facebook,instagram,pinterest}/`), wired in
`config/config.exs`; `BotOAuthController` connects bot accounts.

## Bot flow (publisher) vs user flow (LiveViews)

Two intentionally separate paths:

- **Bot flow** — `RecipePublishWorker` → publisher: applies
  `AI.Bot.RecipeTranslation` + ingredient/unit translations, resolves
  per-language Facebook pages / Pinterest boards from the bot config, writes
  an `AI.Bot.SocialMediaPostLog` row per platform, returns per-platform
  results. Worker retries on `{:error, _}`; platforms with an existing `"ok"`
  post log are skipped unless `force: true`.
- **User flow** — `recipe_details_live/social_media_post_component.ex` and
  `recipe_details_component.ex` post a user's own recipe with the user's
  connected accounts and inline UI feedback. They call the platform clients
  directly and do not write post logs.

The user-flow components duplicate parts of the platform dispatch. Unifying
them onto the publisher would change user-facing behavior (feedback shapes,
no post logs), so it was deferred — known future work.

Daily token refresh:
- `InstagramTokenRefreshWorker` (cron 01:30 UTC) refreshes long-lived Instagram
  tokens.
- `PinterestTokenRefreshWorker` (cron 01:45 UTC) refreshes Pinterest access
  tokens (~30-day lifetime) from the stored refresh token before they expire.
  In addition, the authed Pinterest API calls (`get_boards`/`create_board`/
  `create_pin`) refresh-and-retry once on a `401`, so a token that lapses
  between cron runs recovers transparently.

In both cases invalid tokens (4xx on refresh) are marked stale and surface as
"reconnect" in `/professional/ai-bot/social` and the user's connected-accounts
settings. The OAuth callback (`AuthController`) redirects a connect attempt with
no logged-in user to the login page instead of raising, so a dropped session no
longer reads as a failed connect.

## Copy-ready meal-plan posts (external platforms)

The public published-plan page `/meal-plans/:slug`
(`MehungryWeb.MealPlanLive.Show`) offers two **copy-ready** social posts so a
user can share their week on platforms we don't publish to directly (Instagram,
Pinterest, X/Threads, Facebook, WhatsApp). This is manual copy/paste + native
share — not the `Social.Publisher` fan-out above.

Both strings are built by the pure, testable `MehungryWeb.MealPlanShareText`
(`image_caption/2` + `text_post/2`) from the immutable plan snapshot — no DB, no
IO, so they also render in the synchronous (crawler) page render. The macro
numbers are formatted exactly like the page's `<.macro_tile>` grid (ultimately
`Mehungry.NutrientUtils.macro_summary/1`), so the caption can never drift from
the page.

- **Image + caption** (shown only when `plan.og_image_url` exists): a short
  caption paired with a "Download image" link to the PNG card. For
  Instagram/Pinterest/Facebook.
- **Text post**: a longer, image-free, day-by-day post. Copied via the `Copy`
  JS hook, or pushed to the native share sheet via the `WebShare` hook (extended
  with a `data-text` body) for X/Threads/WhatsApp.

Both carry the plan URL + hashtags (a goal-derived tag is added when the plan
has a `goal_label`), and render in the viewer's locale (Greek weekday labels via
`CalendarLive.Calendar.Locale.day_name/2`).
