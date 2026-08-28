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
| `Mehungry.Social.Pinterest` | HTTPoison | Host comes from `:pinterest_api_base`, set in `runtime.exs` from `PINTEREST_ENV` (`live` → real API, anything else/unset → sandbox). Tokens are not interchangeable between environments — reconnect accounts after switching; the ueberauth strategy and token exchange read the same key. Builds pin links via the `:endpoint_module` runtime seam |

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

Daily token refresh: `InstagramTokenRefreshWorker` (cron 01:30 UTC) refreshes
long-lived Instagram tokens; invalid tokens are marked stale and surface as
"reconnect" in `/professional/ai-bot/social`.
