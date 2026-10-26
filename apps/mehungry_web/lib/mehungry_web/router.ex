defmodule MehungryWeb.Router do
  use MehungryWeb, :router
  import Phoenix.LiveDashboard.Router

  import MehungryWeb.UserAuth
  import MehungryWeb.PathPlug
  import MehungryWeb.RouterHelpers

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(MehungryWeb.Plugs.CookieConsent)
    plug(Plug.CSRFProtection)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {MehungryWeb.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_path_info)
    plug(:fetch_current_user)
    plug(MehungryWeb.Plugs.SetLocale)
    plug(MehungryWeb.Plugs.RedirectProProfile)
  end

  pipeline :admin_browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(MehungryWeb.Plugs.CookieConsent)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {MehungryWeb.LayoutView, :admin_root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_path_info)
    plug(:fetch_current_user)
  end

  pipeline :require_admin do
    plug(MehungryWeb.Plugs.RequireAdmin)
  end

  pipeline :registration_throttle do
    plug(MehungryWeb.Plugs.RegistrationThrottle)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :stripe_webhook do
    plug(:accepts, ["json"])
  end

  # Shared-secret REST API for the non-deployed mehungry_local_ai service.
  pipeline :local_ai_api do
    plug(:accepts, ["json"])
    plug(MehungryWeb.Plugs.RequireLocalAiToken)
  end

  # Prometheus scrape endpoint (text exposition format), token-guarded.
  pipeline :metrics do
    plug(MehungryWeb.Plugs.RequireMetricsToken)
  end

  # Shared-secret REST API for external system integrations.
  pipeline :public_api do
    plug(:accepts, ["json"])
    plug(MehungryWeb.Plugs.RequirePublicApiToken)
  end

  # Public (unauthenticated) OpenAPI spec + Swagger UI for the public API.
  pipeline :api_docs do
    plug(:accepts, ["html", "json"])
  end

  # Mobile JSON API (per-user bearer tokens). `:api_v1` is for 🔓 endpoints that
  # optionally personalize for a logged-in caller; `:api_v1_auth` requires a
  # valid token. See docs/new_dec_specs/mobile_api_spec.md.
  pipeline :api_v1 do
    plug(:accepts, ["json"])
    plug(MehungryWeb.Api.MaybeApiAuthPlug)
    plug(MehungryWeb.Api.V1.SetLocale)
  end

  pipeline :api_v1_auth do
    plug(:accepts, ["json"])
    plug(MehungryWeb.Api.AuthPlug)
    plug(MehungryWeb.Api.V1.SetLocale)
  end

  # Nutritionist-only (`"pro"` tier) mobile API surface (spec §14).
  pipeline :api_v1_nutritionist do
    plug(:accepts, ["json"])
    plug(MehungryWeb.Api.AuthPlug)
    plug(MehungryWeb.Api.RequireNutritionistPlug)
    plug(MehungryWeb.Api.V1.SetLocale)
  end

  scope "/api", MehungryWeb.Api do
    pipe_through(:api)

    post("/parser/parse", ParserController, :parse)
  end

  scope "/api/docs", MehungryWeb.Api do
    pipe_through(:api_docs)

    get("/", DocsController, :ui)
    get("/openapi.json", DocsController, :openapi)
  end

  scope "/api", MehungryWeb.Api do
    pipe_through(:public_api)

    get("/foundemental_foods", FoundementalFoodController, :index)
  end

  # ── Mobile API (/api/v1) ────────────────────────────────────────────────
  # Public (🔓) endpoints — optionally personalized when a bearer token is sent.
  scope "/api/v1", MehungryWeb.Api.V1 do
    pipe_through(:api_v1)

    post("/auth/register", SessionController, :register)
    post("/auth/login", SessionController, :login)
    post("/auth/oauth/:provider", SessionController, :oauth)

    get("/preferences/options", PreferencesController, :options)
    get("/users/:id", ProfileController, :show)

    get("/feed", FeedController, :index)
    get("/recipes/:id", RecipeController, :show)
    get("/recipes/:recipe_id/comments", EngagementController, :comments)
    get("/users/:id/recipes", ProfileController, :user_recipes)

    get("/search", SearchController, :index)
    get("/species", SpeciesController, :index)
    get("/species/:slug", SpeciesController, :show)

    get("/blueprints", BlueprintController, :index)
    get("/blueprints/:slug", BlueprintController, :show)

    post("/feedback", FeedbackController, :create)
  end

  # Authenticated (🔒) endpoints — valid bearer token required.
  scope "/api/v1", MehungryWeb.Api.V1 do
    pipe_through(:api_v1_auth)

    delete("/auth/logout", SessionController, :delete)

    get("/me", ProfileController, :me)
    put("/me/profile", ProfileController, :update)
    put("/me/language", ProfileController, :language)
    get("/me/connected_accounts", ProfileController, :connected_accounts)
    delete("/me/connected_accounts/:provider", ProfileController, :disconnect)

    get("/me/preferences", PreferencesController, :show)
    put("/me/preferences", PreferencesController, :update)

    get("/me/ingredients", IngredientController, :index)
    post("/me/ingredients", IngredientController, :create)
    put("/me/ingredients/:id", IngredientController, :update)
    delete("/me/ingredients/:id", IngredientController, :delete)

    post("/recipes", RecipeController, :create)
    put("/recipes/:id", RecipeController, :update)
    delete("/recipes/:id", RecipeController, :delete)

    get("/me/recipes", ProfileController, :my_recipes)

    post("/recipes/:recipe_id/like", EngagementController, :like)
    delete("/recipes/:recipe_id/like", EngagementController, :unlike)
    post("/recipes/:recipe_id/save", EngagementController, :save)
    delete("/recipes/:recipe_id/save", EngagementController, :unsave)
    post("/recipes/:recipe_id/comments", EngagementController, :create_comment)
    post("/comments/:comment_id/answers", EngagementController, :create_answer)
    post("/comments/:comment_id/vote", EngagementController, :vote_comment)

    post("/users/:id/follow", FollowController, :follow)
    delete("/users/:id/follow", FollowController, :unfollow)

    get("/ingredients/search", SearchController, :ingredients)

    get("/meals", MealController, :index)
    get("/meals/day/:date", MealController, :day)
    get("/meals/day/:date/nutrition", MealController, :nutrition)
    post("/meals", MealController, :create)
    put("/meals/:id", MealController, :update)
    delete("/meals/:id", MealController, :delete)
    post("/meals/:id/consume", MealController, :consume)
    post("/meals/plan-with-ai", MealController, :plan_with_ai)
    get("/meals/plan-with-ai/:job_id", MealController, :plan_status)

    get("/basket", BasketController, :show)
    post("/basket/items", BasketController, :add_item)
    put("/basket/items/:id", BasketController, :update_item)
    delete("/basket/items/:id", BasketController, :delete_item)
    post("/basket/import/recipe/:recipe_id", BasketController, :import_recipe)
    post("/basket/import/meal/:meal_id", BasketController, :import_meal)

    post("/uploads/presign", UploadController, :presign)
    post("/uploads", UploadController, :create)

    get("/subscription", SubscriptionController, :show)
    post("/subscription/checkout", SubscriptionController, :checkout)
    post("/subscription/portal", SubscriptionController, :portal)

    get("/me/invitations", InvitationController, :index)
    post("/me/invitations/:id/accept", InvitationController, :accept)
    post("/me/invitations/:id/decline", InvitationController, :decline)

    get("/me/notifications", NotificationController, :index)
    get("/me/notifications/unread_count", NotificationController, :unread_count)
    post("/me/notifications/read", NotificationController, :read)

    post("/me/devices", DeviceController, :create)
    delete("/me/devices/:token", DeviceController, :delete)
  end

  # Nutritionist portal (🔒 pro tier) — spec §14.
  scope "/api/v1/nutritionist", MehungryWeb.Api.V1 do
    pipe_through(:api_v1_nutritionist)

    get("/clients", NutritionistController, :clients)
    get("/clients/:id", NutritionistController, :client)
    get("/clients/:id/meals", NutritionistController, :client_meals)
    get("/appointments", NutritionistController, :appointments)
    get("/invitations", NutritionistController, :invitations)
    post("/invitations", NutritionistController, :invite)
  end

  scope "/", MehungryWeb do
    pipe_through(:metrics)

    get("/metrics", MetricsController, :index)

    # BeamScope's own Prometheus endpoint. Defined before the `/beam_scope`
    # forward below so it takes precedence and is token-guarded (like /metrics)
    # rather than sitting behind the session-based admin auth on that forward.
    get("/beam_scope/metrics", MetricsController, :beam_scope)
  end

  scope "/api/local_ai", MehungryWeb.Api.LocalAi do
    pipe_through(:local_ai_api)

    get("/pending", PendingController, :index)
    post("/full_text", FullTextController, :create)
    post("/candidates", CandidatesController, :create)
    post("/gi_candidates", GiCandidatesController, :create)

    # Reverse (condition-seeded) phase-aware recommendation extraction.
    get("/condition_pending", ConditionPendingController, :index)
    post("/condition_recommendation_candidates", ConditionRecCandidatesController, :create)
  end

  scope "/auth", MehungryWeb do
    pipe_through(:browser)

    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
    post("/:provider/callback", AuthController, :callback)
    post("/logout", AuthController, :delete)
  end

  scope "/professional", MehungryWeb do
    pipe_through([:admin_browser, :require_authenticated_user])

    live_session :default2,
      on_mount: [MehungryWeb.AdminAuthLive, MehungryWeb.SessionMetrics],
      layout: {MehungryWeb.LayoutView, :admin_live} do
      live("/users", ProfessionalLive.Users, :index)
      live("/user/:id", ProfessionalLive.User, :show)

      live("/files", ProfessionalLive.S3BrowserLive, :index)
      live("/activeusers", ProfessionalLive.ActiveUsers, :index)
      live("/recipes", ProfessionalLive.Recipes, :index)
      live("/myplate-review", ProfessionalLive.MyPlateReview, :index)
      live("/myplate-review/:slug", ProfessionalLive.MyPlateReview, :index)
      live("/gutenberg-review", ProfessionalLive.GutenbergReview, :index)
      live("/gutenberg-review/:book_id", ProfessionalLive.GutenbergReview, :index)
      live("/gutenberg-review/:book_id/:index", ProfessionalLive.GutenbergReview, :index)
      live("/unitools-review", ProfessionalLive.UniToolsReview, :index)
      live("/unitools-review/:dataset_id", ProfessionalLive.UniToolsReview, :index)
      live("/unitools-review/:dataset_id/:index", ProfessionalLive.UniToolsReview, :index)
      live("/ingredients", ProfessionalLive.Ingredients, :index)
      live("/ingredients/:id/edit", ProfessionalLive.IngredientsEdit, :edit)
      live("/ingredients/new", ProfessionalLive.IngredientsCreate, :create)
      live("/ingredients/:id/show", Professional.IngredientLive.Show, :show)

      live("/measurement_units", ProfessionalLive.MeasurementUnits, :index)
      live("/measurement_units/new", ProfessionalLive.MeasurementUnits, :new)
      live("/measurement_units/:id/edit", ProfessionalLive.MeasurementUnits, :edit)

      live("/taxonomy/review", ProfessionalLive.TaxonomyReview, :index)

      live("/science", ProfessionalLive.SciencePipeline, :index)
      live("/science/studies", ProfessionalLive.Studies, :index)
      live("/science/entities", ProfessionalLive.Entities, :index)

      live("/literature", ProfessionalLive.LiteratureRuns, :index)

      live("/compound-candidates", ProfessionalLive.CompoundCandidates, :index)

      # live("/glycemic-index", ProfessionalLive.GlycemicIndex, :index)
      live("/health", ProfessionalLive.HealthConditions, :index)

      live("/usda-schema", ProfessionalLive.UsdaSchema, :index)

      live("/languages", Professional.LanguageLive.Index, :index)
      live("/languages/new", Professional.LanguageLive.Index, :new)
      live("/languages/:id/edit", Professional.LanguageLive.Index, :edit)

      live("/languages/:id", Professional.LanguageLive.Show, :show)
      live("/languages/:id/show/edit", Professional.LanguageLive.Show, :edit)

      live("/translations", ProfessionalLive.TranslationsLive.Index, :index)
      live("/translations/:resource", ProfessionalLive.TranslationsLive.Panel, :index)
      live("/translations/:resource/:id", ProfessionalLive.TranslationsLive.Panel, :show)

      live("/analytics", ProfessionalLive.AnalyticsLive, :index)
      live("/maintenance", ProfessionalLive.MaintenanceLive, :index)

      live("/feedback", ProfessionalLive.FeedbackLive, :index)

      live("/android-beta", ProfessionalLive.AndroidBetaLive, :index)

      live("/ai-bot", AiBotLive.Config, :index)
      live("/ai-bot/new", AiBotLive.Config, :new)
      live("/ai-bot/:id/edit", AiBotLive.Config, :edit)
      live("/ai-bot/review", AiBotLive.ReviewQueue, :index)
      live("/ai-bot/review/:id", AiBotLive.RecipeReview, :show)
      live("/ai-bot/review/:id/translate/:lang", AiBotLive.RecipeTranslate, :show)
      live("/ai-bot/social", AiBotLive.SocialAccounts, :index)

      live("/ai-bot/personas", AiBotLive.Personas, :index)
      live("/ai-bot/personas/new", AiBotLive.Personas, :new)
      live("/ai-bot/personas/:id/edit", AiBotLive.Personas, :edit)
      live("/ai-bot/setups", AiBotLive.Setups, :index)
      live("/ai-bot/setups/new", AiBotLive.Setups, :new)
      live("/ai-bot/setups/:id/edit", AiBotLive.Setups, :edit)
      live("/ai-bot/orders", AiBotLive.Orders, :index)
      live("/ai-bot/orders/new", AiBotLive.Orders, :new)

      live("/ingredients/reconciliation", ProfessionalLive.IngredientReconciliation, :index)
    end
  end

  scope "/auth/bot", MehungryWeb do
    pipe_through([:admin_browser, :require_authenticated_user])
    get("/target/:bot_user_id/:provider", BotOAuthController, :set_target)
  end

  scope "/nutritionist", MehungryWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :nutritionist,
      on_mount: [MehungryWeb.NutritionistAuthLive, MehungryWeb.SessionMetrics],
      layout: {MehungryWeb.LayoutView, :nutritionist_live} do
      live("/", NutritionistLive.Dashboard, :index)
      live("/profile", NutritionistLive.ProfileEdit, :edit)
      live("/invitations", NutritionistLive.Invitations, :index)
      live("/clients", NutritionistLive.Clients, :index)
      live("/clients/import", NutritionistLive.Clients, :import)
      # Legacy roster path — the Records page folded into Clients; redirect bookmarks.
      live("/records", NutritionistLive.Clients, :legacy_redirect)
      live("/records/:id", NutritionistLive.ClientRecord, :show)
      live("/records/:id/edit", NutritionistLive.ClientRecordEditor, :edit)
      live("/clients/:id", NutritionistLive.ClientDetail, :show)
      live("/clients/:id/calendar", NutritionistLive.ClientCalendar, :index)
      live("/clients/:id/calendar/edit/:meal_id", NutritionistLive.ClientCalendar, :edit)
      live("/clients/:id/calendar/:date", NutritionistLive.ClientCalendar, :particular)
      live("/clients/:id/calendar/:date/:title", NutritionistLive.ClientCalendar, :new)
      live("/appointments", NutritionistLive.AppointmentCalendar, :index)
      live("/articles", NutritionistLive.Articles, :index)
      live("/articles/:id/edit", NutritionistLive.ArticleEditor, :edit)

      live("/blueprints", MealBlueprintLive.Index, :index)
      live("/blueprints/new", MealBlueprintLive.Index, :new)
      live("/blueprints/:id/edit", MealBlueprintLive.Editor, :edit)
    end

    # Health-conditions workflow, reusing the public HealthLive / ConditionDetailLive
    # modules but mounted inside the nutritionist panel (its layout + chrome). The
    # injected `nav_section` session flag tells those LiveViews to keep all internal
    # navigation under `/nutritionist/conditions` instead of the public `/:locale/conditions`.
    live_session :nutritionist_conditions,
      on_mount: [MehungryWeb.NutritionistAuthLive, MehungryWeb.SessionMetrics],
      layout: {MehungryWeb.LayoutView, :nutritionist_live},
      session: %{"nav_section" => "nutritionist"} do
      live("/conditions", HealthLive.Index, :index)
      live("/conditions/:id", ConditionDetailLive.Index, :index)
      live("/conditions/:id/food/:species_id", ConditionDetailLive.Index, :show_food)
    end
  end

  scope "/", MehungryWeb do
    pipe_through([:browser, :require_authenticated_user])

    live_session :default,
      on_mount: [MehungryWeb.RestoreLocale, MehungryWeb.UserAuthLive, MehungryWeb.SessionMetrics] do
      localized_live("/notifications/invitations", NutritionistLive.UserInvitations, :index)
      localized_live("/messages", MessagesLive.Index, :index)
      localized_live("/friends", FriendsLive.Index, :index)
      localized_live("/basket", ShoppingBasketLive.Index, :index)
      localized_live("/basket/import_items/:id", ShoppingBasketLive.Index, :import_items)

      localized_live("/calendar", CalendarLive.Index, :index)
      localized_live("/calendar/ondate/:date", CalendarLive.Index, :particular)
      localized_live("/calendar/details/:date", CalendarLive.Index, :nutrition_details)
      localized_live("/calendar/recipe/:recipe_id", CalendarLive.Index, :show_recipe)

      localized_live("/calendar/:start/:title", CalendarLive.Index, :new)

      localized_live("/calendar/:id", CalendarLive.Index, :edit)

      localized_live("/stepper", CreateRecipeLive.Show, :show)
      localized_live("/create_recipe", CreateRecipeLive.Index, :index)
      localized_live("/create_recipe/:recipe_id", CreateRecipeLive.Index, :edit)

      localized_live("/my_ingredients/new", MyIngredientLive.Form, :new)
      localized_live("/my_ingredients/:id/edit", MyIngredientLive.Form, :edit)

      localized_live("/upgrade", UpgradeLive.Index, :index)
    end
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  import Phoenix.LiveDashboard.Router
  import Oban.Web.Router

  scope "/" do
    pipe_through([:admin_browser, :require_authenticated_user, :require_admin])

    forward("/beam_scope", BeamScope.Exporter.Router)

    live_dashboard("/dashboard",
      metrics: MehungryWeb.Telemetry,
      ecto_repos: [Mehungry.Repo]
    )

    # Oban Web — jobs UI (view / retry / cancel background jobs), admin-gated
    # alongside LiveDashboard. See docs; reachable at /oban.
    oban_dashboard("/oban")
  end

  if Mix.env() == :dev do
    pipeline :dev_browser do
      plug(:accepts, ["html"])
      plug(:fetch_session)
      plug(:fetch_live_flash)
      plug(:put_root_layout, {MehungryWeb.LayoutView, :dev_root})
      plug(:protect_from_forgery)
      plug(:put_secure_browser_headers)
    end

    scope "/dev", MehungryWeb do
      pipe_through(:dev_browser)

      # Dev-only Markdown browser / viewer / editor over the repo's docs.
      live("/docs", Dev.MarkdownBrowserLive, :index)
    end

    forward("/dev/mailbox", Plug.Swoosh.MailboxPreview)
  end

  ## Authentication routes

  scope "/webhooks", MehungryWeb do
    pipe_through(:stripe_webhook)
    post("/stripe", StripeWebhookController, :webhook)
  end

  # Deterministic pre-confirmed accounts for third-party/bot integration
  # testing. Gated inside the controller: dev/test always, other envs require a
  # matching TEST_ACCOUNTS_TOKEN. See MehungryWeb.TestAccountsController.
  scope "/test-accounts", MehungryWeb do
    pipe_through(:api)
    get("/", TestAccountsController, :index)
    get("/seed", TestAccountsController, :seed)
    get("/reset", TestAccountsController, :reset)
  end

  scope "/", MehungryWeb do
    pipe_through([:browser])

    live("/privacy_policy", PrivacyPolicyLive, :index)
    get("/health", HealthController, :check)
    get("/sitemap.xml", SitemapController, :index)
    post("/cookie-consent/accept", ConsentController, :accept)
    post("/cookie-consent/decline", ConsentController, :decline)
    # /cookies route goes to CookiesPolicyController, created in Task 4
    get("/cookies", CookiesPolicyController, :index)
    get("/terms", TermsController, :index)
    get("/legal", LegalNoticeController, :index)

    # Retired public condition pages — moved behind /nutritionist/conditions on
    # 2026-10-14 (YMYL / regulated-medical-device risk; see GoneController). They
    # already 404, but Google still shows stale impressions for the indexed URLs;
    # a 410 tells it to drop them. Both the bare and locale-prefixed forms, since
    # the old routes were `localized_live`. Must NOT be re-added to the sitemap.
    get("/conditions", GoneController, :gone)
    get("/conditions/:id", GoneController, :gone)
    get("/conditions/:id/food/:species_id", GoneController, :gone)
    get("/:locale/conditions", GoneController, :gone)
    get("/:locale/conditions/:id", GoneController, :gone)
    get("/:locale/conditions/:id/food/:species_id", GoneController, :gone)

    # One-click unsubscribe from the beta-tester list (link in welcome/invite
    # emails). A plain GET controller so it works without JS and runs exactly
    # once (a LiveView mount would run on both the HTTP and WS passes).
    get("/trial/unsubscribe/:token", TrialController, :unsubscribe)
  end

  scope "/", MehungryWeb do
    pipe_through([:browser, :maybe_require_authenticated_user])

    live_session :default3,
      on_mount: [MehungryWeb.RestoreLocale, MehungryWeb.SessionMetrics],
      layout: {MehungryWeb.LayoutView, :landing_live} do
      localized_live("/welcome", LandingLive, :index)
      localized_live("/trial", TrialLive.Index, :index)
    end

    live_session :maybe,
      on_mount: [MehungryWeb.RestoreLocale, MehungryWeb.MaybeUserAuthLive, MehungryWeb.SessionMetrics] do
      get("/", HomePageController, :home)

      localized_live("/home", HomeLive.Index, :index)
      localized_live("/home/:id", HomeLive.Index, :show_recipe)

      localized_live("/browse", RecipeBrowserLive.Index, :index)
      localized_live("/browse/:id", RecipeBrowserLive.Index, :show_recipe)
      localized_live("/profile", ProfileLive.Index, :index)
      localized_live("/profile/edit", ProfileLive.Index, :edit)
      localized_live("/profile/:id", ProfileLive.Index, :show)
      localized_live("/profile/show_recipe/:recipe_id", ProfileLive.Index, :show_recipe)

      localized_live("/show_recipe/:id", HomeLive.Index, :show_recipe)
      localized_live("/share_social_media/:id/:social_media", HomeLive.Index, :share_social_media)

      localized_live("/search/", RecipeBrowserLive.Index, :index)
      localized_live("/search/hashtag/:hashtag", RecipeBrowserLive.Index, :index)
      localized_live("/search/ingredient/:ingredient", RecipeBrowserLive.Index, :index)
      localized_live("/search/nutrient/:nutrient", RecipeBrowserLive.Index, :index)
      localized_live("/search/:query", RecipeBrowserLive.Index, :index)

      localized_live("/foods", FoodsLive.Index, :index)
      localized_live("/foods/:slug", SpeciesDetailLive.Index, :index)

      localized_live("/blueprints/:slug", BlueprintLive.Show, :show)

      localized_live("/meal-plans", MealPlanLive.Index, :index)
      localized_live("/meal-plans/:slug", MealPlanLive.Show, :show)

      localized_live("/nutritionists", PublicNutritionistLive.Index, :index)
      localized_live("/nutritionists/:slug", PublicNutritionistLive.Show, :show)

      localized_live(
        "/nutritionists/:slug/articles/:article_slug",
        PublicNutritionistLive.Article,
        :show
      )

      localized_live("/feedback", FeedbackLive, :index)
    end

    get("/login", UserSessionController, :new)
    post("/login", UserSessionController, :create)

    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
    get("/users/reset_password", UserResetPasswordController, :new)
    post("/users/reset_password", UserResetPasswordController, :create)
    get("/users/reset_password/:token", UserResetPasswordController, :edit)
    put("/users/reset_password/:token", UserResetPasswordController, :update)
  end

  # Registration routes are rate-limited per IP to blunt scripted signups.
  scope "/", MehungryWeb do
    pipe_through([:browser, :registration_throttle])

    get("/register", UserRegistrationController, :new)
    post("/register", UserRegistrationController, :create)
    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)

    # Claim a login-less account created by a professional on the client's behalf.
    get("/claim/:token", UserClaimController, :edit)
    post("/claim/:token", UserClaimController, :update)
    get("/claim/:token/oauth/:provider", UserClaimController, :oauth_request)
  end

  scope "/", MehungryWeb do
    pipe_through([:browser, :require_authenticated_user])

    get("/users/settings", UserSettingsController, :edit)
    put("/users/settings", UserSettingsController, :update)
    get("/users/settings/confirm_email/:token", UserSettingsController, :confirm_email)
  end

  scope "/", MehungryWeb do
    pipe_through([:browser])

    # Language switch works for anonymous visitors too (swaps the URL locale).
    get("/users/language/:lang", UserLanguageController, :set)

    get("/users/log_out", UserSessionController, :delete)
    get("/users/delete", UserSessionController, :delete_user)

    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
    get("/users/confirm/:token", UserConfirmationController, :edit)
    post("/users/confirm/:token", UserConfirmationController, :update)
  end

  ## Authentication routes
end
