defmodule MehungryWeb.LandingLive do
  use MehungryWeb, :live_view
  use MehungryWeb.Searchable, :transfers_to_search
  use MehungryWeb.Presence, :user_tracking

  import MehungryWeb.SvgComponents
  import Ecto.Query

  @impl true
  def handle_event("resize_chart", %{"width" => width}, socket) do
    for child_id <- socket.assigns.child_ids do
      send_update(MehungryWeb.CalendarLive.Calendar.PieChart, resize: width)
    end

    {:noreply, socket}
  end

  def mount_search(_params, _session, socket) do
    query =
      from(p in Mehungry.Food.Recipe,
        order_by: fragment("RANDOM()"),
        limit: 1
      )

    recipe =
      Mehungry.Repo.one(query)

    {:ok,
     assign(socket,
       scrolled: false,
       recipe: recipe,
       child_ids: [],
       selected_plan: "monthly"
     )}
  end

  def render(assigns) do
    ~H"""
    <!-- Navigation -->
    <nav
      class="fixed top-0 left-0 right-0 z-50 bg-slate-900/95 backdrop-blur-md border-b border-slate-800 transition-all duration-300 h-18"
      style="max-height: 15rem;"
    >
      <div class="container mx-auto px-4 py-3 flex items-center justify-between">
        <.get_logo id="landind-2" class="h-6 w-auto" />

        <div class="hidden md:flex items-center gap-6">
          <a href="#features" class="text-slate-300 hover:text-primary-500 transition">Features</a>
          <a href="#nutrition" class="text-slate-300 hover:text-primary-500 transition">
            Nutrition Data
          </a>
          <a href="#how-it-works" class="text-slate-300 hover:text-primary-500 transition">
            How It Works
          </a>
          <a
            href="#community"
            class="text-slate-300 hover:text-primary-500 transition"
            style="display: none;"
          >
            Community
          </a>
          <a
            href="#pricing"
            class="text-slate-300 hover:text-primary-500 transition"
            style="display: none;"
          >
            Pricing
          </a>
        </div>

        <div class="flex items-center gap-2">
          <a href="/login" class="text-slate-300 hover:text-white transition px-4 py-2">Sign In</a>
          <a
            href="/register"
            class="bg-primary-500 hover:bg-primary-600 text-white px-5 py-2 rounded-lg transition shadow-lg shadow-primary-500/20"
          >
            Get Started
          </a>
        </div>
      </div>
    </nav>

    <!-- Hero Section -->
    <section class="relative pt-32 pb-20 overflow-hidden sm:pt-60">
      <!-- Background gradient -->
      <div class="absolute inset-0 bg-gradient-to-b from-slate-900 via-slate-900 to-slate-800"></div>
      
    <!-- Animated cubes background -->
      <div class="absolute inset-0 opacity-10">
        <div class="absolute top-20 left-10 w-32 h-32 border border-primary-500 rounded-lg animate-pulse">
        </div>
        <div class="absolute bottom-40 right-20 w-24 h-24 border border-secondary-500 rounded-lg animate-bounce">
        </div>
        <div class="absolute top-1/2 left-1/3 w-16 h-16 border border-accent-500 rounded-lg animate-spin">
        </div>
      </div>

      <div class="container mx-auto px-4 relative z-10">
        <div class="max-w-4xl mx-auto text-center">
          <div class="inline-flex items-center gap-2 bg-primary-500/10 border border-primary-500/20 rounded-full px-4 py-1 mb-6">
            <span class="w-2 h-2 bg-primary-500 rounded-full animate-pulse"></span>
            <span class="text-primary-400 text-sm">Powered by USDA FoodData Central</span>
          </div>

          <h1 class="text-5xl md:text-7xl font-bold text-white mb-6">
            Know Exactly What's
            <span class="bg-gradient-to-r from-primary-500 to-primary-300 bg-clip-text text-transparent">
              On Your Plate
            </span>
          </h1>

          <p class="text-xl text-slate-300 mb-8 max-w-2xl mx-auto">
            Track every nutrient, from macronutrients to individual fatty acids.
            M3HUNGRY gives you institutional-grade nutrition analysis for your daily meals.
          </p>

          <div class="flex flex-col sm:flex-row gap-4 justify-center">
            <a
              href="/register"
              class="bg-primary-500 hover:bg-primary-600 text-white px-8 py-3 rounded-lg font-semibold transition shadow-lg shadow-primary-500/30"
            >
              Start Tracking Free
            </a>
            <a
              href="#demo"
              class="border border-slate-600 hover:border-primary-500 text-slate-300 hover:text-white px-8 py-3 rounded-lg font-semibold transition hidden"
            >
              Watch Demo →
            </a>
          </div>

          <div class="flex items-center justify-center gap-8 mt-12 text-slate-400 text-sm">
            <div class="flex items-center gap-2">
              <svg
                class="w-5 h-5 text-secondary-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span>USDA Database</span>
            </div>
            <div class="flex items-center gap-2">
              <svg
                class="w-5 h-5 text-secondary-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span>10,000+ Foods</span>
            </div>
            <div class="flex items-center gap-2">
              <svg
                class="w-5 h-5 text-secondary-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                />
              </svg>
              <span>168 Nutrients Tracked</span>
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Features Grid -->
    <section id="features" class="py-8 bg-slate-800" style="scroll-margin-top: 20rem;">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
            Everything You Need to <span class="text-primary-500">Master Your Nutrition</span>
          </h2>
          <p class="text-slate-400 max-w-2xl mx-auto">
            From deep nutrient analysis to community sharing, M3HUNGRY empowers you to make informed food choices.
          </p>
        </div>

        <div class="grid md:grid-cols-3 gap-8">
          <!-- Feature 1: Deep Nutrition -->
          <div class="bg-slate-700/50 rounded-xl p-6 border border-slate-600 hover:border-primary-500/50 transition group">
            <div class="w-12 h-12 bg-primary-500/10 rounded-lg flex items-center justify-center mb-4 group-hover:bg-primary-500/20 transition">
              <svg
                class="w-6 h-6 text-primary-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
                />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-white mb-2">Deep Nutrition Analysis</h3>
            <p class="text-slate-400">
              Track every nutrient including individual fatty acids (PUFA, MUFA, SFA), vitamins, minerals, and amino acids from USDA data.
            </p>
          </div>
          
    <!-- Feature 2: Recipe Builder -->
          <div class="bg-slate-700/50 rounded-xl p-6 border border-slate-600 hover:border-secondary-500/50 transition group">
            <div class="w-12 h-12 bg-secondary-500/10 rounded-lg flex items-center justify-center mb-4 group-hover:bg-secondary-500/20 transition">
              <svg
                class="w-6 h-6 text-secondary-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M3 12h18M3 6h18M3 18h18"
                />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-white mb-2">Smart Recipe Builder</h3>
            <p class="text-slate-400">
              Create recipes by combining ingredients. See instant nutrition calculations with portion-based gram weight conversions.
            </p>
          </div>
          
    <!-- Feature 3: Community Sharing -->
          <div class="bg-slate-700/50 rounded-xl p-6 border border-slate-600 hover:border-accent-500/50 transition group">
            <div class="w-12 h-12 bg-accent-500/10 rounded-lg flex items-center justify-center mb-4 group-hover:bg-accent-500/20 transition">
              <svg
                class="w-6 h-6 text-accent-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
            </div>
            <h3 class="text-xl font-semibold text-white mb-2">Community Driven</h3>
            <p class="text-slate-400">
              Share your recipes, comment on others, and discover new meal ideas from a community of health-conscious cooks.
            </p>
          </div>
        </div>
      </div>
    </section>

    <!-- Nutrition Demo Accordion -->
    <section
      id="nutrition"
      class=" bg-slate-900"
      style="scroll-margin-top: 14rem; padding-top: 2.5rem; padding-bottom: 2.5rem;"
    >
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
            See the <span class="text-secondary-500">Difference</span>
          </h2>
          <p class="text-slate-400 max-w-2xl mx-auto">
            Most apps show calories and macros. M3HUNGRY shows you everything.
          </p>
        </div>

        <div class="max-w-2xl mx-auto bg-slate-800 rounded-xl border border-slate-700 overflow-hidden">
          <div class="bg-slate-700 px-6 py-3 border-b border-slate-600">
            <h3 class="text-white font-semibold">{@recipe.title}</h3>
            <p class="text-slate-400 text-sm">Nutrition Facts per serving</p>
          </div>
          {MehungryWeb.RecipeComponents.recipe_nutrients(@recipe)}
        </div>
      </div>
    </section>

    <!-- How It Works -->
    <section id="how-it-works" class="py-20 bg-slate-800" style="scroll-margin-top: 12rem;">
      >
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
            How <span class="text-primary-500">M3HUNGRY</span> Works
          </h2>
          <p class="text-slate-400 max-w-2xl mx-auto">
            Three simple steps to master your nutrition
          </p>
        </div>

        <div class="grid md:grid-cols-4 gap-8 max-w-4xl mx-auto">
          <div class="text-center">
            <div class="w-16 h-16 bg-primary-500/10 rounded-full flex items-center justify-center mx-auto mb-4 border border-primary-500/30">
              <span class="text-2xl font-bold text-primary-500">1</span>
            </div>
            <h3 class="text-white font-semibold mb-2">Search Foods</h3>
            <p class="text-slate-400 text-sm">Browse 10,000+ foods from the USDA database</p>
          </div>

          <div class="text-center">
            <div class="w-16 h-16 bg-secondary-500/10 rounded-full flex items-center justify-center mx-auto mb-4 border border-secondary-500/30">
              <span class="text-2xl font-bold text-secondary-500">2</span>
            </div>
            <h3 class="text-white font-semibold mb-2">Create Recipes</h3>
            <p class="text-slate-400 text-sm">Create your own recipes or get inspired by community</p>
          </div>
          <div class="text-center">
            <div class="w-16 h-16 bg-primary-500/10 rounded-full flex items-center justify-center mx-auto mb-4 border border-secondary-500/30">
              <span class="text-2xl font-bold text-secondary-500">3</span>
            </div>
            <h3 class="text-white font-semibold mb-2">Plan your meals</h3>
            <p class="text-slate-400 text-sm">
              Combine recipes and final foods to create the ideal plan
            </p>
          </div>

          <div class="text-center">
            <div class="w-16 h-16 bg-accent-500/10 rounded-full flex items-center justify-center mx-auto mb-4 border border-accent-500/30">
              <span class="text-2xl font-bold text-accent-500">4</span>
            </div>
            <h3 class="text-white font-semibold mb-2">Analyze & Share</h3>
            <p class="text-slate-400 text-sm">Get deep nutrient insights and share with community</p>
          </div>
        </div>
      </div>
    </section>

    <!-- USDA Data Section -->
    <section class="py-12 bg-gradient-to-b from-slate-900 to-slate-800">
      <div class="container mx-auto px-4">
        <div class="flex flex-col md:flex-row items-center gap-12">
          <div class="flex-1">
            <div class="inline-flex items-center gap-2 bg-primary-500/10 border border-primary-500/20 rounded-full px-3 py-1 mb-4">
              <span class="text-primary-400 text-xs font-medium">POWERED BY</span>
            </div>
            <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
              Professional <span class="text-secondary-500">Meal Planning </span> Experience
            </h2>
            <p class="text-slate-300 mb-6">
              Every nutrient comes directly from the USDA's authoritative database.
              Track everything from energy and macros to specific fatty acids like
              PUFA 18:2 n-6 and DHA.
            </p>
            <div class="grid grid-cols-2 gap-4">
              <div class="flex items-center gap-2">
                <svg
                  class="w-5 h-5 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span class="text-slate-300 text-sm">168+ Nutrients Tracked</span>
              </div>
              <div class="flex items-center gap-2">
                <svg
                  class="w-5 h-5 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span class="text-slate-300 text-sm">Foundation & SR Legacy Foods</span>
              </div>
              <div class="flex items-center gap-2">
                <svg
                  class="w-5 h-5 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span class="text-slate-300 text-sm">Fatty Acid Profiles</span>
              </div>
              <div class="flex items-center gap-2">
                <svg
                  class="w-5 h-5 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                <span class="text-slate-300 text-sm">Vitamin & Mineral Analysis</span>
              </div>
            </div>
          </div>
          <div class="flex-1">
            <div class="bg-slate-800 rounded-xl p-6 border border-slate-700">
              <MehungryWeb.CalendarLive.Calendar.Widget.card_meal
                img_url={@recipe.image_url}
                card_meal_text="text-white"
                recipe={@recipe}
                cooking_portions="1"
                consume_portions="1"
                actual_meal={
                  %{cooking_portions: 1, consume_portions: 1, recipe: @recipe, id: "landing_id"}
                }
                title="Breakfast"
                myself="asdf"
                id="landing_id"
              />
              {MehungryWeb.CalendarLive.Calendar.Widget.get_chart(
                [
                  %{
                    start_dt: NaiveDateTime.local_now(),
                    recipe_user_meals: [
                      %{
                        recipe_nutrients: @recipe.nutrients,
                        cooking_portions: 1,
                        consume_portions: 1,
                        recipe: @recipe,
                        id: "landing_id",
                        start_dt: NaiveDateTime.local_now()
                      }
                    ]
                  }
                ],
                Date.utc_today(),
                "text-white"
              )}
            </div>
          </div>
        </div>
      </div>
    </section>

    <!-- Community Section -->
    <section id="community" class="py-20 bg-slate-800" style="scroll-margin-top: 14rem; display: none">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
            Join a Growing <span class="text-accent-500">Community</span>
          </h2>
          <p class="text-slate-400 max-w-2xl mx-auto">
            10,000+ home cooks are already tracking their nutrition with M3HUNGRY
          </p>
        </div>

        <div class="grid md:grid-cols-3 gap-6 max-w-4xl mx-auto">
          <div class="bg-slate-700/50 rounded-xl p-6 border border-slate-600">
            <div class="flex items-center gap-2 mb-4">
              <div class="w-10 h-10 rounded-full bg-primary-500/20 flex items-center justify-center text-primary-500 font-bold">
                JD
              </div>
              <div>
                <div class="text-white text-sm font-medium">Jordan D.</div>
                <div class="text-slate-400 text-xs">⭐⭐⭐⭐⭐</div>
              </div>
            </div>
            <p class="text-slate-300 text-sm">
              "The level of detail in nutrient tracking is incredible. I can finally see exactly what fatty acids I'm eating!"
            </p>
          </div>

          <div class="bg-slate-700/50 rounded-xl p-6 border border-slate-600">
            <div class="flex items-center gap-2 mb-4">
              <div class="w-10 h-10 rounded-full bg-secondary-500/20 flex items-center justify-center text-secondary-500 font-bold">
                SM
              </div>
              <div>
                <div class="text-white text-sm font-medium">Sarah M.</div>
                <div class="text-slate-400 text-xs">⭐⭐⭐⭐⭐</div>
              </div>
            </div>
            <p class="text-slate-300 text-sm">
              "The recipe builder with gram weight conversion is a game changer. No more guessing portions!"
            </p>
          </div>

          <div class="bg-slate-700/50 rounded-xl p-6 border border-slate-600">
            <div class="flex items-center gap-2 mb-4">
              <div class="w-10 h-10 rounded-full bg-accent-500/20 flex items-center justify-center text-accent-500 font-bold">
                MC
              </div>
              <div>
                <div class="text-white text-sm font-medium">Mike C.</div>
                <div class="text-slate-400 text-xs">⭐⭐⭐⭐⭐</div>
              </div>
            </div>
            <p class="text-slate-300 text-sm">
              "Love sharing recipes with friends. The community features make healthy eating social and fun!"
            </p>
          </div>
        </div>
      </div>
    </section>

    <!-- Pricing Section -->
    <section id="pricing" class="py-20 bg-slate-900" style="scroll-margin-top: 14rem; display: none">
      <div class="container mx-auto px-4">
        <div class="text-center mb-12">
          <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
            Simple, <span class="text-primary-500">Transparent</span> Pricing
          </h2>
          <p class="text-slate-400 max-w-2xl mx-auto">
            Start free, upgrade when you need more
          </p>
        </div>

        <div class="flex flex-col md:flex-row gap-8 justify-center items-center">
          <!-- Free Tier -->
          <div class="bg-slate-800 rounded-xl p-8 border border-slate-700 w-full max-w-sm">
            <h3 class="text-xl font-bold text-white mb-2">Free</h3>
            <div class="text-3xl font-bold text-white mb-4">
              $0<span class="text-slate-400 text-base font-normal">/month</span>
            </div>
            <ul class="space-y-3 mb-8">
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Unlimited food search
              </li>
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Up to 10 recipes
              </li>
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-secondary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Basic nutrition tracking
              </li>
            </ul>
            <a
              href="/register"
              class="block w-full text-center border border-slate-600 hover:border-primary-500 text-slate-300 hover:text-white py-2 rounded-lg transition"
            >
              Get Started
            </a>
          </div>
          
    <!-- Pro Tier (Highlighted) -->
          <div class="bg-slate-800 rounded-xl p-8 border-2 border-primary-500 shadow-xl shadow-primary-500/10 w-full max-w-sm relative">
            <div class="absolute -top-3 left-1/2 transform -translate-x-1/2 bg-primary-500 text-white text-xs font-bold px-3 py-1 rounded-full">
              MOST POPULAR
            </div>
            <h3 class="text-xl font-bold text-white mb-2">Pro</h3>
            <div class="text-3xl font-bold text-white mb-4">
              $9.99<span class="text-slate-400 text-base font-normal">/month</span>
            </div>
            <ul class="space-y-3 mb-8">
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-primary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Unlimited recipes & ingredients
              </li>
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-primary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Full fatty acid analysis
              </li>
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-primary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Export nutrition data
              </li>
              <li class="flex items-center gap-2 text-slate-300 text-sm">
                <svg
                  class="w-4 h-4 text-primary-500"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M5 13l4 4L19 7"
                  />
                </svg>
                Priority support
              </li>
            </ul>
            <a
              href="/register?plan=pro"
              class="block w-full text-center bg-primary-500 hover:bg-primary-600 text-white py-2 rounded-lg transition shadow-lg shadow-primary-500/30"
            >
              Start Pro Trial
            </a>
          </div>
        </div>
      </div>
    </section>

    <!-- CTA Section -->
    <section class="py-20 bg-gradient-to-r from-primary-600 to-primary-800">
      <div class="container mx-auto px-4 text-center">
        <h2 class="text-3xl md:text-4xl font-bold text-white mb-4">
          Ready to Master Your Nutrition?
        </h2>
        <p class="text-primary-100 mb-8 max-w-2xl mx-auto">
          Join thousands of users who already know exactly what's on their plate.
        </p>
        <a
          href="/register"
          class="inline-block bg-white text-primary-600 hover:bg-slate-100 px-8 py-3 rounded-lg font-semibold transition shadow-lg"
        >
          Start Tracking Free →
        </a>
      </div>
    </section>

    <!-- Footer -->
    <footer class="bg-slate-900 border-t border-slate-800 py-12">
      <div class="container mx-auto px-4">
        <div class="flex flex-col md:flex-row justify-between items-center">
          <div class="mb-6 md:mb-0">
            <.get_logo id="landing" class="h-8 w-auto" />
            <p class="text-slate-500 text-sm mt-2">Know exactly what's on your plate.</p>
          </div>
          <div class="flex gap-8">
            <a href="#features" class="text-slate-400 hover:text-primary-500 text-sm transition">
              Features
            </a>
            <a href="#pricing" class="text-slate-400 hover:text-primary-500 text-sm transition">
              Pricing
            </a>
            <a href="/privacy_policy" class="text-slate-400 hover:text-primary-500 text-sm transition">
              Privacy
            </a>
          </div>
        </div>
        <div class="border-t border-slate-800 mt-8 pt-8 text-center text-slate-500 text-xs">
          &copy; 2025 M3HUNGRY. All rights reserved. Powered by USDA FoodData Central.
        </div>
      </div>
    </footer>
    """
  end
end
