defmodule MehungryWeb.Router do
  use MehungryWeb, :router

  import MehungryWeb.UserAuth
  import MehungryWeb.PathPlug

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
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
    plug :fetch_live_flash
    plug :put_root_layout, {MehungryWeb.LayoutView, :admin_root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_path_info
    plug :fetch_current_user
  end





  pipeline :api do
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
    live_session :default2, on_mount: MehungryWeb.AdminAuthLive , layout: {MehungryWeb.LayoutView, :admin_live}
do
      live "/users", ProfessionalLive.Users, :index
      live "/user/:id", ProfessionalLive.User, :show

      live "/ingredients", ProfessionalLive.Ingredients, :index
    end
  end

  scope "/", MehungryWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :default, on_mount: MehungryWeb.UserAuthLive do
      live "/", HomeLive.Index, :index
      live "/post/:id", HomeLive.Show, :show

      live "/select", SelectAlpineLive, :index

      live "/profile", ProfileLive.Index, :index
      live "/profile/edit", ProfileLive.Index, :edit
      live "/profile/:id", ProfileLive.Index, :show

      live "/browse", RecipeBrowseLive.Index, :index
      live "/browse/:id", RecipeBrowseLive.Index, :show
      live "/browse_prepop/:search_term", :searc_prepop
      live "/basket", ShoppingBasketLive.Index, :index
      live "/basket/import_items/:id", ShoppingBasketLive.Index, :import_items

      live "/calendar", CalendarLive.Index, :index
      live "/calendar/ondate/:date", CalendarLive.Index, :particular

      live "/calendar/:start/:end", CalendarLive.Index, :new

      live "/calendar/:id", CalendarLive.Index, :edit

      live "/create_recipe", CreateRecipeLive.Index, :index
      live "/create_recipe/add_ingredient", CreateRecipeLive.Index, :add_ingredient
      live "/create_recipe/:temp_id/edit_ingredient", CreateRecipeLive.Index, :edit_ingredient
      live "/create_recipe/:uuid/delete_ingredient", CreateRecipeLive.Index, :delete_ingredient
      live "/survey", SurveyLive, :index
      live "/admin-dashboard", Admin.DashboardLive

      live "/posts", PostLive.Index, :index
      live "/posts/new", PostLive.Index, :new
      live "/posts/:id/edit", PostLive.Index, :edit

      live "/posts/:id", PostLive.Show, :show
      live "/posts/:id/show/edit", PostLive.Show, :edit

      live "/comments", CommentLive.Index, :index
      live "/comments/new", CommentLive.Index, :new
      live "/comments/:id/edit", CommentLive.Index, :edit

      live "/comments/:id", CommentLive.Show, :show
      live "/comments/:id/show/edit", CommentLive.Show, :edit

      live "/comment_answers", CommentAnswerLive.Index, :index
      live "/comment_answers/new", CommentAnswerLive.Index, :new
      live "/comment_answers/:id/edit", CommentAnswerLive.Index, :edit

      live "/comment_answers/:id", CommentAnswerLive.Show, :show
      live "/comment_answers/:id/show/edit", CommentAnswerLive.Show, :edit
    end

    live "/ingredients", IngredientLive.Index, :index
    live "/ingredients/new", IngredientLive.Index, :new
    live "/ingredients/:id/edit", IngredientLive.Index, :edit

    live "/ingredients/:id", IngredientLive.Show, :show
    live "/ingredients/:id/show/edit", IngredientLive.Show, :edit

    live "/categories", CategoryLive.Index, :index
    live "/categories/new", CategoryLive.Index, :new
    live "/categories/:id/edit", CategoryLive.Index, :edit

    live "/categories/:id", CategoryLive.Show, :show
    live "/categories/:id/show/edit", CategoryLive.Show, :edit

    live "/measurement_units", MeasurementUnitLive.Index, :index
    live "/measurement_units/new", MeasurementUnitLive.Index, :new
    live "/measurement_units/:id/edit", MeasurementUnitLive.Index, :edit

    live "/measurement_units/:id", MeasurementUnitLive.Show, :show
    live "/measurement_units/:id/show/edit", MeasurementUnitLive.Show, :edit
  end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser
      live_dashboard "/dashboard", metrics: MehungryWeb.Telemetry
    end
  end

  ## Authentication routes

  scope "/", MehungryWeb do
    pipe_through [:browser]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
    get "/users/reset_password", UserResetPasswordController, :new
    post "/users/reset_password", UserResetPasswordController, :create
    get "/users/reset_password/:token", UserResetPasswordController, :edit
    put "/users/reset_password/:token", UserResetPasswordController, :update
  end

  scope "/", MehungryWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/users/settings", UserSettingsController, :edit
    put "/users/settings", UserSettingsController, :update
    get "/users/settings/confirm_email/:token", UserSettingsController, :confirm_email
  end

  scope "/", MehungryWeb do
    pipe_through [:browser]

    get "/users/log_out", UserSessionController, :delete
    get "/users/confirm", UserConfirmationController, :new
    post "/users/confirm", UserConfirmationController, :create
    get "/users/confirm/:token", UserConfirmationController, :edit
    post "/users/confirm/:token", UserConfirmationController, :update
  end

  ## Authentication routes
end
