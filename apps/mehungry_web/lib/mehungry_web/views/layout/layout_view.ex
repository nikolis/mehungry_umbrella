defmodule MehungryWeb.LayoutView do
  use MehungryWeb, :html
  alias Phoenix.LiveView.JS
  alias MehungryWeb.SvgComponents

  embed_templates "templates/*"
  embed_templates "templates/menu/*"

  def get_main_content_container_class(_conn) do
    "main-content-container"
  end

  @doc """
  Whether to show the first-visit language chooser to an unrecognized visitor.

  Shown only on public live surfaces when **all** hold: not logged in, the
  visitor has not already picked a language this session, the request URL
  carries no explicit `/:locale` prefix (a bare entry — a prefixed URL already
  expresses a language), and a supported locale is in play (nil on the
  English-only admin/nutritionist surfaces, which never prompt).
  """
  def show_language_chooser?(assigns) do
    is_nil(assigns[:current_user]) and
      assigns[:locale_selected] != true and
      assigns[:url_locale_present] != true and
      MehungryWeb.Locale.supported?(assigns[:locale])
  end

  @doc """
  First-visit language selection modal for unrecognized visitors.

  Each option is a real anchor to `/users/language/:lang` (the existing public
  switcher, which persists the choice + swaps the current path's locale prefix),
  so it works without JS and stays crawlable. `return_to` is bound client-side
  to the current path so the visitor lands back on the same page in their
  chosen language even when the `Referer` header is stripped. A client-side
  `localStorage` flag keeps a dismissed/chosen chooser from reappearing on
  subsequent bare navigations within the browser.
  """
  attr :current_user, :any, default: nil
  attr :locale, :string, default: nil
  attr :locale_selected, :boolean, default: false
  attr :url_locale_present, :boolean, default: false

  def language_chooser(assigns) do
    ~H"""
    <div
      :if={show_language_chooser?(assigns)}
      id="language-chooser"
      x-data="{ open: !window.localStorage.getItem('langChosen'), choose() { window.localStorage.setItem('langChosen', '1') } }"
      x-show="open"
      x-cloak
      role="dialog"
      aria-modal="true"
      aria-label="Choose your language"
      class="fixed inset-0 z-[60] flex items-center justify-center bg-ink/80 backdrop-blur-sm px-4"
    >
      <div class="relative w-full max-w-sm rounded-2xl border border-ink-panel2 bg-ink-panel p-6 shadow-2xl text-center">
        <button
          type="button"
          @click="choose(); open = false"
          aria-label="Close"
          class="absolute right-4 top-4 text-parchment-dim hover:text-parchment transition-colors"
        >
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </button>

        <div class="mb-1 text-3xl">🍅</div>
        <h2 class="text-lg font-semibold text-parchment">Choose your language</h2>
        <p class="mt-1 text-sm text-parchment-dim">Επιλέξτε τη γλώσσα σας</p>

        <div class="mt-5 grid grid-cols-2 gap-3">
          <a
            href="/users/language/en"
            x-bind:href="'/users/language/en?return_to=' + encodeURIComponent(window.location.pathname + window.location.search)"
            @click="choose()"
            class="flex flex-col items-center gap-1 rounded-xl border border-ink-panel2 bg-ink px-4 py-4 text-parchment hover:border-paprika hover:bg-ink-panel2 transition-colors"
          >
            <span class="text-2xl">🇬🇧</span>
            <span class="text-sm font-semibold">English</span>
          </a>
          <a
            href="/users/language/el"
            x-bind:href="'/users/language/el?return_to=' + encodeURIComponent(window.location.pathname + window.location.search)"
            @click="choose()"
            class="flex flex-col items-center gap-1 rounded-xl border border-ink-panel2 bg-ink px-4 py-4 text-parchment hover:border-paprika hover:bg-ink-panel2 transition-colors"
          >
            <span class="text-2xl">🇬🇷</span>
            <span class="text-sm font-semibold">Ελληνικά</span>
          </a>
        </div>
      </div>
    </div>
    """
  end

  attr :conn, :any, required: true

  def cookie_consent_banner(assigns) do
    ~H"""
    <%= if @conn.assigns[:cookie_consent] == :pending and
          not String.starts_with?(@conn.request_path, "/nutritionist") do %>
      <div
        id="cookie-consent-banner"
        role="dialog"
        aria-label="Cookie consent"
        class="fixed bottom-0 left-0 right-0 z-50 flex flex-col gap-3 border-t border-slate-700 bg-slate-900/95 px-4 py-4 backdrop-blur-sm sm:flex-row sm:items-center sm:justify-between sm:px-8"
      >
        <p class="text-sm text-slate-300">
          We use cookies to keep you logged in and to understand how the site is used.
          <a href="/cookies" class="ml-1 underline hover:text-white">Cookie Policy</a>
        </p>
        <div class="flex shrink-0 gap-3">
          <form action="/cookie-consent/decline" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button
              type="submit"
              class="btn btn-sm btn-ghost border border-slate-600 text-slate-300 hover:bg-slate-700"
            >
              Decline
            </button>
          </form>
          <form action="/cookie-consent/accept" method="post">
            <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
            <button type="submit" class="btn btn-sm btn-primary">
              Accept
            </button>
          </form>
        </div>
      </div>
    <% end %>
    """
  end

  attr :current_user, :any
  attr :current_language, :string, default: "en"
  attr :inner_content, :any, default: nil

  def get_menu(assigns) do
    ~H"""
    <.main_menu
      current_user={@current_user}
      current_language={@current_language}
      inner_content={@inner_content}
    />
    <.mobile_menu current_user={@current_user} current_language={@current_language} />
    <a
      href="/feedback"
      class="md:hidden fixed bottom-20 right-4 z-50 flex items-center gap-2 px-3 py-2 rounded-full bg-slate-700 text-slate-200 text-xs font-medium shadow-lg hover:bg-slate-600 transition-colors"
    >
      <.icon name="hero-chat-bubble-left-ellipsis" class="h-4 w-4" /> Feedback
    </a>
    """
  end

  def sidebar_nav_links(assigns) do
    ~H"""
    <div x-data="{ open: false }">
      <!-- Mobile top bar: the discoverable menu affordance on small screens.
           The sidebar itself lives in the root layout (outside the LiveView DOM),
           so the open/close toggle uses Alpine — phx-click/JS would never fire here. -->
      <header class="md:hidden fixed top-0 inset-x-0 z-40 flex items-center justify-between h-14 px-4 bg-ink border-b border-ink-panel2/60">
        <a href="/" class="block w-28">
          {SvgComponents.get_logo(%{id: "admin-topbar"})}
        </a>
        <button
          type="button"
          @click="open = true"
          aria-label="Open admin menu"
          class="flex items-center gap-2 py-2 pl-3 pr-2 -mr-2 rounded-lg text-parchment hover:bg-ink-panel transition"
        >
          <span class="text-sm font-semibold">Admin</span>
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M4 6h16M4 12h16M4 18h16"
            />
          </svg>
        </button>
      </header>

      <!-- Backdrop (mobile only; desktop sidebar is persistent) -->
      <div
        x-show="open"
        x-transition.opacity
        @click="open = false"
        class="md:hidden fixed inset-0 bg-black/50 z-40"
        x-cloak
      />

      <!-- Sidebar: persistent on desktop, slide-in drawer on mobile.
           The slide transform is driven by the #nav_bar_admin CSS rules
           (which beat Tailwind's utility specificity); Alpine toggles .open. -->
      <nav
        id="nav_bar_admin"
        x-bind:class="{ 'open': open }"
        class="fixed top-0 left-0 h-full w-64 bg-ink border-r border-ink-panel2/60 z-50 flex flex-col shadow-2xl transition-transform duration-300"
      >
        <!-- Logo -->
        <div class="flex items-center justify-between px-5 py-5 border-b border-ink-panel2/60">
          <a href="/" class="block w-32">
            {SvgComponents.get_logo(%{id: "admin-sidebar"})}
          </a>
          <button
            type="button"
            class="md:hidden p-1.5 rounded-lg text-parchment-dim hover:text-white hover:bg-ink-panel transition"
            @click="open = false"
            aria-label="Close admin menu"
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
          <span class="text-xs font-semibold text-parchment-dim uppercase tracking-wider">Admin Panel</span>
        </div>

        <!-- Nav links (tapping one closes the drawer on mobile) -->
        <div class="flex-1 px-3 space-y-1 overflow-y-auto" @click="open = false">
        <.admin_link href="/professional/analytics" icon="hero-chart-bar" label="Analytics" />
        <.admin_link href="/professional/users" icon="hero-users" label="Users" />
        <.admin_link href="/professional/recipes" icon="hero-book-open" label="Recipes" />
        <.admin_link href="/professional/ingredients" icon="hero-beaker" label="Ingredients" />
        <.admin_link href="/professional/measurement_units" icon="hero-scale" label="Units" />
        <.admin_link
          href="/professional/onboarding-questions/user"
          icon="hero-queue-list"
          label="Onboarding Qs"
        />
        <.admin_link href="/professional/languages" icon="hero-language" label="Languages" />
        <.admin_link href="/professional/translations" icon="hero-globe-alt" label="Translations" />
        <.admin_link href="/professional/files" icon="hero-folder-open" label="Files" />
        <.admin_link
          href="/professional/feedback"
          icon="hero-chat-bubble-left-ellipsis"
          label="Feedback"
        />
        <.admin_link href="/professional/ai-bot" icon="hero-cpu-chip" label="AI Bot" />
        <.admin_link
          href="/professional/android-beta"
          icon="hero-device-phone-mobile"
          label="Android Beta"
        />
        <.admin_link
          href="/professional/taxonomy/review"
          icon="hero-rectangle-stack"
          label="Taxonomy"
        />
        <.admin_link href="/professional/health" icon="hero-heart" label="Health" />
        <.admin_link
          href="/professional/ingredients/reconciliation"
          icon="hero-arrow-path"
          label="Reconcile"
        />
        <.admin_link
          href="/professional/usda-schema"
          icon="hero-squares-2x2"
          label="USDA Schema"
        />
      </div>

      <!-- Footer -->
      <div class="px-5 py-4 border-t border-ink-panel2/60">
        <a
          href="/"
          class="flex items-center gap-2 text-parchment-dim hover:text-white text-sm transition"
        >
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
    </div>
    """
  end

  attr :current_user, :any

  def nutritionist_sidebar(assigns) do
    ~H"""
    <!-- Mobile toggle -->
    <button
      id="nutritionist_menu_button"
      class="md:hidden fixed bottom-4 right-4 z-50 w-12 h-12 flex items-center justify-center rounded-full bg-paprika hover:bg-paprika-soft text-ink transition shadow-lg"
      phx-click={
        JS.toggle_class("open", to: "#nav_bar_nutritionist")
        |> JS.toggle_class("hidden", to: "#nutritionist_backdrop")
      }
    >
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M4 6h16M4 12h16M4 18h16"
        />
      </svg>
    </button>

    <!-- Backdrop (mobile) -->
    <div
      id="nutritionist_backdrop"
      class="fixed inset-0 bg-black/50 z-40 hidden md:hidden"
      phx-click={
        JS.toggle_class("open", to: "#nav_bar_nutritionist")
        |> JS.toggle_class("hidden", to: "#nutritionist_backdrop")
      }
    />

    <!-- Sidebar -->
    <nav
      id="nav_bar_nutritionist"
      class="fixed top-0 left-0 h-full w-64 bg-ink-panel border-r border-ink-panel2 z-50 flex flex-col shadow-2xl transition-transform duration-300 -translate-x-full md:translate-x-0"
    >
      <div class="flex items-center justify-between px-5 py-5 border-b border-ink-panel2">
        <a
          href="/nutritionist"
          class="block w-32"
          style="--logo-text-color: #F4EEDD; --logo-tagline-color: transparent;"
        >
          {SvgComponents.get_logo(%{id: "nutritionist-sidebar"})}
        </a>
        <button
          class="md:hidden p-1.5 rounded-lg text-parchment-dim hover:text-parchment hover:bg-ink-panel2 transition"
          phx-click={
            JS.toggle_class("open", to: "#nav_bar_nutritionist")
            |> JS.toggle_class("hidden", to: "#nutritionist_backdrop")
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

      <div class="px-5 py-3">
        <span class="text-xs font-semibold text-basil uppercase tracking-wider">Nutritionist Panel</span>
      </div>

      <div class="flex-1 px-3 space-y-1 overflow-y-auto">
        <.nutritionist_link href="/nutritionist" icon="hero-squares-2x2" label="Dashboard" />
        <.nutritionist_link
          href="/nutritionist/profile"
          icon="hero-identification"
          label="My Profile"
        />
        <.nutritionist_link
          href="/nutritionist/clients"
          icon="hero-user-group"
          label="My Clients"
          badge={
            if(@current_user,
              do: Mehungry.Professionals.count_unread_messages_for(@current_user.id),
              else: 0
            )
          }
        />
        <.nutritionist_link
          href="/nutritionist/blueprints"
          icon="hero-clipboard-document-list"
          label="Blueprints"
        />
        <.nutritionist_link href="/nutritionist/invitations" icon="hero-envelope" label="Invitations" />
        <.nutritionist_link
          href="/nutritionist/onboarding-questions"
          icon="hero-queue-list"
          label="Onboarding Qs"
        />
        <.nutritionist_link
          href="/nutritionist/appointments"
          icon="hero-calendar-days"
          label="Appointments"
        />
        <.nutritionist_link
          href="/nutritionist/articles"
          icon="hero-document-text"
          label="Articles"
        />
        <.nutritionist_link
          href="/nutritionist/research"
          icon="hero-academic-cap"
          label="Research"
        />
      </div>

      <div class="px-5 py-4 border-t border-ink-panel2">
        <a
          href="/home"
          class="flex items-center gap-2 text-parchment-dim hover:text-parchment text-sm transition"
        >
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
  attr :badge, :integer, default: 0

  defp nutritionist_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="flex items-center gap-3 px-3 py-2.5 rounded-lg text-parchment-dim hover:text-parchment hover:bg-ink-panel2 transition-colors text-sm font-medium"
    >
      <.icon name={@icon} class="w-5 h-5 flex-shrink-0" />
      {@label}
      <%= if @badge > 0 do %>
        <span class="ml-auto min-w-5 h-5 px-1.5 inline-flex items-center justify-center rounded-full bg-red-500 text-white text-[10px] font-bold">
          {@badge}
        </span>
      <% end %>
    </a>
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp admin_link(assigns) do
    ~H"""
    <a
      href={@href}
      class="flex items-center gap-3 px-3 py-2.5 rounded-lg text-parchment hover:text-white hover:bg-ink-panel transition text-sm font-medium group"
    >
      <.icon
        name={@icon}
        class="w-5 h-5 text-parchment-dim group-hover:text-paprika-soft transition flex-shrink-0"
      />
      {@label}
    </a>
    """
  end
end
