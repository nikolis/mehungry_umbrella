defmodule MehungryWeb.LayoutView do
  use MehungryWeb, :html
  alias Phoenix.LiveView.JS
  alias MehungryWeb.SvgComponents

  embed_templates "templates/*"
  embed_templates "templates/menu/*"

  def get_main_content_container_class(_conn) do
    "main-content-container"
  end

  attr :current_user, :any
  attr :current_language, :string, default: "en"

  def get_menu(assigns) do
    ~H"""
    <.main_menu
      current_user={@current_user}
      current_language={@current_language}
      inner_content={@inner_content}
    />
    <.mobile_menu current_user={@current_user} />
    <a
      href="/feedback"
      class="md:hidden fixed bottom-20 right-4 z-50 flex items-center gap-2 px-3 py-2 rounded-full bg-slate-700 text-slate-200 text-xs font-medium shadow-lg hover:bg-slate-600 transition-colors"
    >
      <.icon name="hero-chat-bubble-left-ellipsis" class="h-4 w-4" />
      Feedback
    </a>
    """
  end

  def sidebar_nav_links(assigns) do
    ~H"""
    <!-- Backdrop -->
    <div
      id="admin_backdrop"
      class="fixed inset-0 bg-black/50 z-40 hidden"
      phx-click={
        JS.toggle_class("open", to: "#nav_bar_admin")
        |> JS.toggle_class("hidden", to: "#admin_backdrop")
      }
    />

    <!-- Toggle button -->
    <button
      id="admin_menu_button"
      class="fixed bottom-4 right-4 z-50 w-12 h-12 flex items-center justify-center rounded-full bg-primary-500 hover:bg-primary-600 text-white transition shadow-lg"
      phx-click={
        JS.toggle_class("open", to: "#nav_bar_admin")
        |> JS.toggle_class("hidden", to: "#admin_backdrop")
        |> JS.toggle_class("sidebar-open", to: "#admin_menu_button")
      }
    >
      <svg id="icon_hamburger" class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M4 6h16M4 12h16M4 18h16"
        />
      </svg>
    </button>

    <!-- Sidebar -->
    <nav
      id="nav_bar_admin"
      class="fixed top-0 left-0 h-full w-64 bg-slate-900 border-r border-slate-700/60 z-50 flex flex-col shadow-2xl transition-transform duration-300 -translate-x-full"
    >
      <!-- Logo -->
      <div class="flex items-center justify-between px-5 py-5 border-b border-slate-700/60">
        <a href="/" class="block w-32">
          {SvgComponents.get_logo(%{id: "admin-sidebar"})}
        </a>
        <button
          class="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition"
          phx-click={
            JS.toggle_class("open", to: "#nav_bar_admin")
            |> JS.toggle_class("hidden", to: "#admin_backdrop")
          }
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>
      
    <!-- Label -->
      <div class="px-5 py-3">
        <span class="text-xs font-semibold text-slate-500 uppercase tracking-wider">Admin Panel</span>
      </div>
      
    <!-- Nav links -->
      <div class="flex-1 px-3 space-y-1 overflow-y-auto">
        <.admin_link href="/professional/analytics" icon="hero-chart-bar" label="Analytics" />
        <.admin_link href="/professional/users" icon="hero-users" label="Users" />
        <.admin_link href="/professional/seo" icon="hero-magnifying-glass" label="SEO" />
        <.admin_link href="/professional/ingredients" icon="hero-beaker" label="Ingredients" />
        <.admin_link href="/professional/languages" icon="hero-language" label="Languages" />
        <.admin_link href="/professional/files" icon="hero-folder-open" label="Files" />
        <.admin_link href="/professional/visits" icon="hero-map-pin" label="Visits" />
        <.admin_link href="/professional/feedback" icon="hero-chat-bubble-left-ellipsis" label="Feedback" />
      </div>
      
    <!-- Footer -->
      <div class="px-5 py-4 border-t border-slate-700/60">
        <a href="/" class="flex items-center gap-2 text-slate-400 hover:text-white text-sm transition">
          <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          Back to app
        </a>
      </div>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp admin_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="flex items-center gap-3 px-3 py-2.5 rounded-lg text-slate-300 hover:text-white hover:bg-slate-800 transition text-sm font-medium group"
    >
      <.icon
        name={@icon}
        class="w-5 h-5 text-slate-400 group-hover:text-primary-400 transition flex-shrink-0"
      />
      {@label}
    </a>
    """
  end
end
