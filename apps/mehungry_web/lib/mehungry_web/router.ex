defmodule MehungryWeb.Router do
  use MehungryWeb, :router
  import Phoenix.LiveDashboard.Router

  import MehungryWeb.UserAuth
  import MehungryWeb.PathPlug

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
      live "/ingredients", ProfessionalLive.Ingredients, :index
      live "/ingredients/:id/edit", ProfessionalLive.IngredientsEdit, :edit
      live "/ingredients/new", ProfessionalLive.IngredientsCreate, :create
      live "/ingredients/:id/show", Professional.IngredientLive.Show, :show

      live "/measurement_units", ProfessionalLive.MeasurementUnits, :index
      live "/measurement_units/new", ProfessionalLive.MeasurementUnits, :new
      live "/measurement_units/:id/edit", ProfessionalLive.MeasurementUnits, :edit

      live "/taxonomy/review", ProfessionalLive.TaxonomyReview, :index

      live "/literature", ProfessionalLive.LiteratureRuns, :index

      live "/compound-candidates", ProfessionalLive.CompoundCandidates, :index

      live "/languages", Professional.LanguageLive.Index, :index
      live "/languages/new", Professional.LanguageLive.Index, :new
      live "/languages/:id/edit", Professional.LanguageLive.Index, :edit

      live "/languages/:id", Professional.LanguageLive.Show, :show
      live "/languages/:id/show/edit", Professional.LanguageLive.Show, :edit

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
      live "/clients/:id/calendar/:date", NutritionistLive.ClientCalendar, :particular
      live "/appointments", NutritionistLive.AppointmentCalendar, :index
    end
  end

  scope "/", MehungryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :default, on_mount: MehungryWeb.UserAuthLive do
      live "/notifications/invitations", NutritionistLive.UserInvitations, :index
      live "/basket", ShoppingBasketLive.Index, :index
      live "/basket/import_items/:id", ShoppingBasketLive.Index, :import_items

      live "/calendar", CalendarLive.Index, :index
      live "/calendar/ondate/:date", CalendarLive.Index, :particular
      live "/calendar/details/:date", CalendarLive.Index, :nutrition_details

      live "/calendar/:start/:title", CalendarLive.Index, :new

      live "/calendar/:id", CalendarLive.Index, :edit

      live "/stepper", CreateRecipeLive.Show, :show
      live "/create_recipe", CreateRecipeLive.Index, :index
      live "/create_recipe/:recipe_id", CreateRecipeLive.Index, :edit

      live "/upgrade", UpgradeLive.Index, :index
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
        timeline: MehungryWeb.QueryTimelinePage
      ]
  end

  if Mix.env() == :dev do
    forward "/dev/mailbox", Plug.Swoosh.MailboxPreview
  end

  ## Authentication routes

  scope "/webhooks", MehungryWeb do
    pipe_through :stripe_webhook
    post "/stripe", StripeWebhookController, :webhook
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
      layout: {MehungryWeb.LayoutView, :landing_live} do
      live "/welcome", LandingLive, :index
    end

    live_session :maybe, on_mount: MehungryWeb.MaybeUserAuthLive do
      get "/", HomePageController, :home

      live "/home", HomeLive.Index, :index
      live "/home/:id", HomeLive.Index, :show_recipe

      live "/browse", RecipeBrowserLive.Index, :index
      live "/browse/:id", RecipeBrowserLive.Index, :show_recipe
      live "/profile", ProfileLive.Index, :index
      live "/profile/edit", ProfileLive.Index, :edit
      live "/profile/:id", ProfileLive.Index, :show
      live "/profile/show_recipe/:recipe_id", ProfileLive.Index, :show_recipe

      live "/show_recipe/:id", HomeLive.Index, :show_recipe
      live "/share_social_media/:id/:social_media", HomeLive.Index, :share_social_media

      live "/search/", RecipeBrowserLive.Index, :index
      live "/search/hashtag/:hashtag", RecipeBrowserLive.Index, :index
      live "/search/ingredient/:ingredient", RecipeBrowserLive.Index, :index
      live "/search/:query", RecipeBrowserLive.Index, :index

      live "/foods", FoodsLive.Index, :index
      live "/foods/:slug", FoodDetailLive.Index, :index

      live "/conditions", HealthLive.Index, :index
      live "/conditions/:id", ConditionDetailLive.Index, :index

      live "/feedback", FeedbackLive, :index
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

    get "/users/language/:lang", UserLanguageController, :set
    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
  end

  scope "/", MehungryWeb do
    pipe_through [:browser]

    get "/users/log_out", UserSessionController, :delete
    get "/users/delete", UserSessionController, :delete_user

    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
  end

  ## Authentication routes
end
