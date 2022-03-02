defmodule MehungryWeb.Router do
  use MehungryWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {MehungryWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MehungryWeb do
    pipe_through :browser

    live "/browse", RecipeBrowseLive.Index, :index
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

    live "/create_recipe", CreateRecipeLive.Index, :index
    live "/create_recipe/add_ingredient", CreateRecipeLive.Index, :add_ingredient
    live "/create_recipe/:uuid/edit_ingredient", CreateRecipeLive.Index, :edit_ingredient
    live "/create_recipe/:uuid/delete_ingredient", CreateRecipeLive.Index, :delete_ingredient

    get "/", PageController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MehungryWeb do
  #   pipe_through :api
  # end

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
end
