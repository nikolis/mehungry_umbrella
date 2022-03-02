defmodule MehungryApi.Router do
  use MehungryApi, :router

  import MehungryApi.UserAuth

  alias MehungryApi.Guardian

  """
    pipeline :browser do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :fetch_live_flash
      plug :put_root_layout, {MehungryApi.LayoutView, :root}
      plug :protect_from_forgery
      plug :put_secure_browser_headers
      plug :fetch_current_user
    end
  """

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, {MehungryApi.LayoutView, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
    plug(:fetch_current_user)
    plug(OpenApiSpex.Plug.PutApiSpec, module: MehungryApi.ApiSpec)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(CORSPlug, origin: "*")
    plug(OpenApiSpex.Plug.PutApiSpec, module: MehungryApi.ApiSpec)
  end

  pipeline :jwt_authenticated do
    plug(Guardian.AuthPipeline)
  end

  scope "/api/swagger" do
    forward("/", PhoenixSwagger.Plug.SwaggerUI,
      otp_app: :mehungry_api,
      swagger_file: "swagger.json"
    )
  end

  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through(:browser)
      live_dashboard("/dashboard", metrics: MehungryApi.Telemetry)

      get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
      get("/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/openapi")
    end
  end

  scope "/", MehungryApi do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
    get("/users/reset_password", UserResetPasswordController, :new)
    post("/users/reset_password", UserResetPasswordController, :create)
    get("/users/reset_password/:token", UserResetPasswordController, :edit)
    put("/users/reset_password/:token", UserResetPasswordController, :update)
  end

  scope "/", PentoWeb do
    pipe_through([:browser])
    delete("/users/log_out", UserSessionController, :delete)
    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
    get("/users/confirm/:token", UserConfirmationController, :confirm)
  end

  scope "/api/v1/", MehungryApi do
    pipe_through([:api])

    get("/languages", LanguagesController, :index)
  end

  scope "/api/v1/", MehungryApi do
    # pipe_through [:api, :jwt_authenticated]
    pipe_through([:api, :jwt_authenticated])

    get("/ingredient/search/:name/:language", IngredientController, :search)

    # resources "/ingredient", IngredientController,
    # only: [:show, :index]

    resources("/recipe", RecipeController, only: [:create, :show, :update, :delete, :index])
    resources("/user_meal", UserMealController, only: [:create, :show, :update, :delete, :index])
    get("/recipe/search/:search_term", RecipeController, :search)
    get("/user/recipe/", RecipeController, :index_user_recipes)
    # get("/recipe/user/like/:recipe_id", RecipeController, :like)

    resources("/measurement_unit", MeasurementUnitController,
      only: [:create, :show, :update, :delete, :index]
    )

    get("/measurement_unit/search/:name/:language", MeasurementUnitController, :search)

    get("/category", CategoryController, :index)

    resources("/plan", MealPlanController, only: [:create, :show, :update, :delete, :index])
    get("/user/:id", UserController, :get)
    get("/user/search/:user_name", UserController, :search_user)
    get("/user/follow/:user_id", UserController, :follow_user)
    get("/user/likes/:user_id", LikeController, :get_likes)
  end

  scope "/api/v1", MehungryApi do
    pipe_through(:api)

    # post("/login/facebook", LoginController, :login_by_facebook_token)
    # post("/login/credentials", LoginController, :login_with_credential)
    resources("/users", UserController, only: [:show])
    post("/register", AuthController, :register_user)
    post("/credential_login", AuthController, :login_with_credential)
  end

  scope "/", MehungryApi do
    pipe_through(:browser)

    # get "/*path", PageController, :index
  end

  def swagger_info do
    %{
      info: %{
        version: "1.0",
        title: "Mehungry",
        basePath: "/api/v1"
      }
    }
  end

  ## Authentication routes

  scope "/", MehungryApi do
    pipe_through([:browser, :redirect_if_user_is_authenticated])

    get("/users/register", UserRegistrationController, :new)
    post("/users/register", UserRegistrationController, :create)
    get("/users/log_in", UserSessionController, :new)
    post("/users/log_in", UserSessionController, :create)
    get("/users/reset_password", UserResetPasswordController, :new)
    post("/users/reset_password", UserResetPasswordController, :create)
    get("/users/reset_password/:token", UserResetPasswordController, :edit)
    put("/users/reset_password/:token", UserResetPasswordController, :update)
  end

  scope "/", MehungryApi do
    pipe_through([:browser, :require_authenticated_user])

    get("/users/settings", UserSettingsController, :edit)
    put("/users/settings", UserSettingsController, :update)
    get("/users/settings/confirm_email/:token", UserSettingsController, :confirm_email)
  end

  scope "/", MehungryApi do
    pipe_through([:browser])

    delete("/users/log_out", UserSessionController, :delete)
    get("/users/confirm", UserConfirmationController, :new)
    post("/users/confirm", UserConfirmationController, :create)
    get("/users/confirm/:token", UserConfirmationController, :confirm)
  end
end
