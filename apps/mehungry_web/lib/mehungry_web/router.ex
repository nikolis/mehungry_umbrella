defmodule MehungryWeb.Router do
  use MehungryWeb, :router
  import Phoenix.LiveDashboard.Router

  import MehungryWeb.UserAuth
  import MehungryWeb.PathPlug
  import MehungryWeb.RouterHelpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug MehungryWeb.Plugs.CookieConsent
    plug MehungryWeb.VisitorPlug
    plug Plug.CSRFProtection
    plug :fetch_live_flash
    plug :put_root_layout, {MehungryWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_path_info
    plug :fetch_current_user
    plug MehungryWeb.Plugs.SetLocale
  end

  pipeline :admin_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug MehungryWeb.Plugs.CookieConsent
    plug MehungryWeb.VisitorPlug
    plug :fetch_live_flash
    plug :put_root_layout, {MehungryWeb.LayoutView, :admin_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_path_info
    plug :fetch_current_user
  end

  pipeline :require_admin do
    plug MehungryWeb.Plugs.RequireAdmin
  end

  pipeline :registration_throttle do
    plug MehungryWeb.Plugs.RegistrationThrottle
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :stripe_webhook do
    plug :accepts, ["json"]
  end

  # Shared-secret REST API for the non-deployed mehungry_local_ai service.
  pipeline :local_ai_api do
    plug :accepts, ["json"]
    plug MehungryWeb.Plugs.RequireLocalAiToken
  end

  scope "/api", MehungryWeb.Api do
    pipe_through :api

    post "/parser/parse", ParserController, :parse
  end

  scope "/api/local_ai", MehungryWeb.Api.LocalAi do
    pipe_through :local_ai_api

    get "/pending", PendingController, :index
    post "/full_text", FullTextController, :create
    post "/candidates", CandidatesController, :create
    get "/metrics", MetricsController, :index
  end

  scope "/auth", MehungryWeb do
    pipe_through :browser

    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
    post("/:provider/callback", AuthController, :callback)
    post("/logout", AuthController, :delete)
  end

  scope "/professional", MehungryWeb do
    pipe_through [:admin_browser, :require_authenticated_user]

    live_session :default2,
      on_mount: MehungryWeb.AdminAuthLive,
      layout: {MehungryWeb.LayoutView, :admin_live} do
      live "/users", ProfessionalLive.Users, :index
      live "/user/:id", ProfessionalLive.User, :show

      live "/files", ProfessionalLive.S3BrowserLive, :index
      live "/activeusers", ProfessionalLive.ActiveUsers, :index
      live "/recipes", ProfessionalLive.Recipes, :index
      live "/ingredients", ProfessionalLive.Ingredients, :index
      live "/ingredients/:id/edit", ProfessionalLive.IngredientsEdit, :edit
      live "/ingredients/new", ProfessionalLive.IngredientsCreate, :create
      live "/ingredients/:id/show", Professional.IngredientLive.Show, :show

      live "/measurement_units", ProfessionalLive.MeasurementUnits, :index
      live "/measurement_units/new", ProfessionalLive.MeasurementUnits, :new
      live "/measurement_units/:id/edit", ProfessionalLive.MeasurementUnits, :edit

      live "/taxonomy/review", ProfessionalLive.TaxonomyReview, :index

      live "/science", ProfessionalLive.SciencePipeline, :index
      live "/science/studies", ProfessionalLive.Studies, :index
      live "/science/entities", ProfessionalLive.Entities, :index

      live "/literature", ProfessionalLive.LiteratureRuns, :index

      live "/compound-candidates", ProfessionalLive.CompoundCandidates, :index

      live "/health", ProfessionalLive.HealthConditions, :index

      live "/usda-schema", ProfessionalLive.UsdaSchema, :index

      live "/languages", Professional.LanguageLive.Index, :index
      live "/languages/new", Professional.LanguageLive.Index, :new
      live "/languages/:id/edit", Professional.LanguageLive.Index, :edit

      live "/languages/:id", Professional.LanguageLive.Show, :show
      live "/languages/:id/show/edit", Professional.LanguageLive.Show, :edit

      live "/translations", ProfessionalLive.TranslationsLive.Index, :index
      live "/translations/:resource", ProfessionalLive.TranslationsLive.Panel, :index
      live "/translations/:resource/:id", ProfessionalLive.TranslationsLive.Panel, :show

      live "/analytics", ProfessionalLive.AnalyticsLive, :index
      live "/seo", ProfessionalLive.SeoLive, :index
      live "/maintenance", ProfessionalLive.MaintenanceLive, :index

      live "/visits", VisitLive.Index, :index
      live "/visits/:ip_address", VisitLive.Show, :show

      live "/feedback", ProfessionalLive.FeedbackLive, :index

      live "/ai-bot", AiBotLive.Config, :index
      live "/ai-bot/new", AiBotLive.Config, :new
      live "/ai-bot/:id/edit", AiBotLive.Config, :edit
      live "/ai-bot/review", AiBotLive.ReviewQueue, :index
      live "/ai-bot/review/:id", AiBotLive.RecipeReview, :show
      live "/ai-bot/review/:id/translate/:lang", AiBotLive.RecipeTranslate, :show
      live "/ai-bot/social", AiBotLive.SocialAccounts, :index

      live "/ai-bot/personas", AiBotLive.Personas, :index
      live "/ai-bot/personas/new", AiBotLive.Personas, :new
      live "/ai-bot/personas/:id/edit", AiBotLive.Personas, :edit
      live "/ai-bot/setups", AiBotLive.Setups, :index
      live "/ai-bot/setups/new", AiBotLive.Setups, :new
      live "/ai-bot/setups/:id/edit", AiBotLive.Setups, :edit
      live "/ai-bot/orders", AiBotLive.Orders, :index
      live "/ai-bot/orders/new", AiBotLive.Orders, :new

      live "/taxonomy/review", ProfessionalLive.TaxonomyReview, :index
      live "/ingredients/reconciliation", ProfessionalLive.IngredientReconciliation, :index
    end
  end

  scope "/auth/bot", MehungryWeb do
    pipe_through [:admin_browser, :require_authenticated_user]
    get "/target/:bot_user_id/:provider", BotOAuthController, :set_target
  end

  scope "/nutritionist", MehungryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :nutritionist,
      on_mount: MehungryWeb.NutritionistAuthLive,
      layout: {MehungryWeb.LayoutView, :nutritionist_live} do
      live "/", NutritionistLive.Dashboard, :index
      live "/invitations", NutritionistLive.Invitations, :index
      live "/clients", NutritionistLive.Clients, :index
      live "/clients/:id", NutritionistLive.ClientDetail, :show
      live "/clients/:id/calendar", NutritionistLive.ClientCalendar, :index
      live "/clients/:id/calendar/edit/:meal_id", NutritionistLive.ClientCalendar, :edit
      live "/clients/:id/calendar/:date", NutritionistLive.ClientCalendar, :particular
      live "/clients/:id/calendar/:date/:title", NutritionistLive.ClientCalendar, :new
      live "/appointments", NutritionistLive.AppointmentCalendar, :index
    end
  end

  scope "/", MehungryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :default, on_mount: [MehungryWeb.RestoreLocale, MehungryWeb.UserAuthLive] do
      localized_live "/notifications/invitations", NutritionistLive.UserInvitations, :index
      localized_live "/friends", FriendsLive.Index, :index
      localized_live "/basket", ShoppingBasketLive.Index, :index
      localized_live "/basket/import_items/:id", ShoppingBasketLive.Index, :import_items

      localized_live "/calendar", CalendarLive.Index, :index
      localized_live "/calendar/ondate/:date", CalendarLive.Index, :particular
      localized_live "/calendar/details/:date", CalendarLive.Index, :nutrition_details
      localized_live "/calendar/recipe/:recipe_id", CalendarLive.Index, :show_recipe

      localized_live "/calendar/:start/:title", CalendarLive.Index, :new

      localized_live "/calendar/:id", CalendarLive.Index, :edit

      localized_live "/stepper", CreateRecipeLive.Show, :show
      localized_live "/create_recipe", CreateRecipeLive.Index, :index
      localized_live "/create_recipe/:recipe_id", CreateRecipeLive.Index, :edit

      localized_live "/my_ingredients/new", MyIngredientLive.Form, :new
      localized_live "/my_ingredients/:id/edit", MyIngredientLive.Form, :edit

      localized_live "/upgrade", UpgradeLive.Index, :index
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

  scope "/" do
    pipe_through [:admin_browser, :require_authenticated_user, :require_admin]

    forward "/beam_scope", BeamScope.Exporter.Router

    live_dashboard "/dashboard",
      metrics: MehungryWeb.Telemetry,
      ecto_repos: [Mehungry.Repo],
      additional_pages: [
        errors: MehungryWeb.ErrorsPage,
        queries: MehungryWeb.QueryTimesPage,
        endpoints: MehungryWeb.EndpointTimesPage,
        timeline: MehungryWeb.QueryTimelinePage,
        local_ai_rate: MehungryWeb.LocalAiRatePage
      ]
  end

  if Mix.env() == :dev do
    pipeline :dev_browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :put_root_layout, {MehungryWeb.LayoutView, :dev_root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
    end

    scope "/dev", MehungryWeb do
      pipe_through :dev_browser

      # Dev-only Markdown browser / viewer / editor over the repo's docs.
      live "/docs", Dev.MarkdownBrowserLive, :index
    end

    forward "/dev/mailbox", Plug.Swoosh.MailboxPreview
  end

  ## Authentication routes

  scope "/webhooks", MehungryWeb do
    pipe_through :stripe_webhook
    post "/stripe", StripeWebhookController, :webhook
  end

  # Deterministic pre-confirmed accounts for third-party/bot integration
  # testing. Gated inside the controller: dev/test always, other envs require a
  # matching TEST_ACCOUNTS_TOKEN. See MehungryWeb.TestAccountsController.
  scope "/test-accounts", MehungryWeb do
    pipe_through :api
    get "/", TestAccountsController, :index
    get "/seed", TestAccountsController, :seed
    get "/reset", TestAccountsController, :reset
  end

  scope "/", MehungryWeb do
    pipe_through [:browser]

    live "/privacy_policy", PrivacyPolicyLive, :index
    get "/health", HealthController, :check
    get "/sitemap.xml", SitemapController, :index
    post "/cookie-consent/accept", ConsentController, :accept
    post "/cookie-consent/decline", ConsentController, :decline
    # /cookies route goes to CookiesPolicyController, created in Task 4
    get "/cookies", CookiesPolicyController, :index
  end

  scope "/", MehungryWeb do
    pipe_through [:browser, :maybe_require_authenticated_user]

    live_session :default3,
      on_mount: MehungryWeb.RestoreLocale,
      layout: {MehungryWeb.LayoutView, :landing_live} do
      localized_live "/welcome", LandingLive, :index
    end

    live_session :maybe, on_mount: [MehungryWeb.RestoreLocale, MehungryWeb.MaybeUserAuthLive] do
      get "/", HomePageController, :home

      localized_live "/home", HomeLive.Index, :index
      localized_live "/home/:id", HomeLive.Index, :show_recipe

      localized_live "/browse", RecipeBrowserLive.Index, :index
      localized_live "/browse/:id", RecipeBrowserLive.Index, :show_recipe
      localized_live "/profile", ProfileLive.Index, :index
      localized_live "/profile/edit", ProfileLive.Index, :edit
      localized_live "/profile/:id", ProfileLive.Index, :show
      localized_live "/profile/show_recipe/:recipe_id", ProfileLive.Index, :show_recipe

      localized_live "/show_recipe/:id", HomeLive.Index, :show_recipe
      localized_live "/share_social_media/:id/:social_media", HomeLive.Index, :share_social_media

      localized_live "/search/", RecipeBrowserLive.Index, :index
      localized_live "/search/hashtag/:hashtag", RecipeBrowserLive.Index, :index
      localized_live "/search/ingredient/:ingredient", RecipeBrowserLive.Index, :index
      localized_live "/search/:query", RecipeBrowserLive.Index, :index

      localized_live "/foods", FoodsLive.Index, :index
      localized_live "/foods/:slug", SpeciesDetailLive.Index, :index

      localized_live "/conditions", HealthLive.Index, :index
      localized_live "/conditions/:id", ConditionDetailLive.Index, :index
      localized_live "/conditions/:id/food/:species_id", ConditionDetailLive.Index, :show_food

      localized_live "/feedback", FeedbackLive, :index
    end

    get "/login", UserSessionController, :new
    post "/login", UserSessionController, :create

    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  # Registration routes are rate-limited per IP to blunt scripted signups.
  scope "/", MehungryWeb do
    pipe_through [:browser, :registration_throttle]

    get "/register", UserRegistrationController, :new
    post "/register", UserRegistrationController, :create
    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
  end

  scope "/", MehungryWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
  end

  scope "/", MehungryWeb do
    pipe_through [:browser]

    # Language switch works for anonymous visitors too (swaps the URL locale).
    get "/users/language/:lang", UserLanguageController, :set

    get "/users/log_out", UserSessionController, :delete
    get "/users/delete", UserSessionController, :delete_user

    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
  end

  ## Authentication routes
end
