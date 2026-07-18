# Social media publishing

## Seam

`Mehungry.SocialMediaPublisherBehaviour` defines `publish_recipe/5`.
The canonical implementation is **`Mehungry.SocialMediaPublisher`** (core).
`RecipePublishWorker` resolves the module at runtime:

```elixir
Application.get_env(:mehungry, :social_media_publisher, Mehungry.SocialMediaPublisher)
```

- `config/test.exs` sets the key to `Mehungry.SocialMediaPublisherStub`.
- `MehungryWeb.SocialMediaPublisher` is a deprecated defdelegate shim kept in
  case an environment config still names it.

## Platform clients (all in core)

| Client | Transport | Notes |
|---|---|---|
| `Mehungry.Instagram` (+ `Instagram.Client` behind `Instagram.ClientBehaviour`) | HTTPoison | Long-lived token lifecycle in `Instagram.Token`; captions capped at 2200 chars by `Instagram.Caption`; stubbed in tests via `:instagram_client` |
| `Mehungry.Api.Facebook` | HTTPoison | Page posts via stored page tokens on `facebook_token` |
| `Mehungry.Api.Pinterest` | HTTPoison | **Currently pointed at the Pinterest sandbox API** (`@api_base`) — restore the production URL after the demo. Builds pin links via the `:endpoint_module` runtime seam |

OAuth strategies for connecting accounts stay in the web app
(`mehungry_web/ueberauth/strategy/{facebook,instagram,pinterest}/`), wired in
`config/config.exs`; `BotOAuthController` connects bot accounts.

## Bot flow (publisher) vs user flow (LiveViews)

Two intentionally separate paths:

- **Bot flow** — `RecipePublishWorker` → publisher: applies
  `AiBot.RecipeTranslation` + ingredient/unit translations, resolves
  per-language Facebook pages / Pinterest boards from the bot config, writes
  an `AiBot.SocialMediaPostLog` row per platform, returns per-platform
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
