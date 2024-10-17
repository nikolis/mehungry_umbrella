defmodule MehungryWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use MehungryWeb, :controller
      use MehungryWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """

  # in sync with css/shared/_media_queries.scss

  def controller do
    quote do
      use Phoenix.Controller, namespace: MehungryWeb

      import Plug.Conn
      import MehungryWeb.Gettext
      alias MehungryWeb.Router.Helpers, as: Routes
    end
  end

  def html do
    quote do
      use Phoenix.Component
      import Phoenix.View

      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      unquote(view_helpers())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/mehungry_web/templates",
        namespace: MehungryWeb

      # Import convenience functions from controllers
      import Phoenix.Controller,
        only: [get_flash: 1, get_flash: 2, view_module: 1, view_template: 1]

      # Include shared imports and aliases for views
      unquote(view_helpers())
    end
  end

  def static_paths, do: ~w(css js assets fonts images favicon.ico robots.txt)

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: MehungryWeb.Endpoint,
        router: MehungryWeb.Router,
        statics: MehungryWeb.static_paths()
    end
  end

  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import MehungryWeb.Gettext
    end
  end

  def live_view do
    quote do
      use Phoenix.LiveView,
        layout: {MehungryWeb.LayoutView, :live}

      alias Phoenix.LiveView.JS
      import MehungryWeb.LiveUtils
      unquote(view_helpers())
    end
  end

  def live_component do
    quote do
      use Phoenix.LiveComponent

      alias Phoenix.LiveView.JS
      import MehungryWeb.LiveUtils
      unquote(view_helpers())
    end
  end

  def stateless_component do
    quote do
      use Phoenix.Component

      alias Phoenix.LiveView.JS
      import MehungryWeb.LiveUtils
      unquote(verified_routes())
    end
  end

  defp view_helpers do
    quote do
      # Use all HTML functionality (forms, tags, etc)
      import Phoenix.HTML
      import Phoenix.HTML.Form
      use PhoenixHTMLHelpers
      import Phoenix.LiveView.Helpers
      import MehungryWeb.LiveHelpers
      import Phoenix.Component
      import MehungryWeb.CoreComponents

      # Import basic rendering functionality (render, render_layout, etc)
      import Phoenix.View
      import HeexIgnore

      import MehungryWeb.ErrorHelpers
      import MehungryWeb.Gettext
      alias MehungryWeb.Router.Helpers, as: Routes

      # Routes generation with the ~p sigil
      unquote(verified_routes())
    end
  end

  def chart_live do
    quote do
      unquote(chart_helpers())
    end
  end

  defp chart_helpers do
    quote do
      import MehungryWeb.BarChart
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
