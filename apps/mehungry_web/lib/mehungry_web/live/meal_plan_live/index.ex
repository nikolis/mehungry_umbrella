defmodule MehungryWeb.MealPlanLive.Index do
  @moduledoc """
  Public, crawlable index of published weekly meal plans (`/meal-plans`).

  This is the SEO hub for meal planning: a single indexable URL that links to
  every public `/meal-plans/:slug` page, giving Googlebot an internal crawl path
  to those plans beyond the sitemap and a page that can itself rank for
  head terms like "weekly meal plans". Rendered **synchronously** (plans loaded
  in `handle_params`) so the disconnected crawler render already carries the full
  list, mirroring `MealPlanLive.Show` and `BlueprintLive.Show`.
  """
  use MehungryWeb, :live_view

  import MehungryWeb.BlueprintComponents

  alias Mehungry.PublishedPlans

  @base_url "https://www.m3hungry.com"

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_new(socket, :current_user, fn -> nil end)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    plans = PublishedPlans.list_public_plans_detailed()

    {:noreply,
     socket
     |> assign(:plans, plans)
     |> assign_seo(plans)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="browse-page min-h-screen bg-ink text-parchment p-4">
      <div class="mx-auto max-w-6xl md:pt-4 md:pl-2">
        <nav class="text-sm text-parchment-dim mb-3" aria-label="Breadcrumb">
          <.link navigate={~p"/home"} class="hover:text-parchment">Home</.link>
          <span class="mx-1">›</span>
          <span class="text-parchment">Meal Plans</span>
        </nav>

        <div class="mb-6">
          <h1 class="text-3xl font-display font-medium text-parchment flex items-center gap-3">
            <svg class="w-8 h-8 text-paprika" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
            Weekly Meal Plans
          </h1>
          <p class="text-parchment-dim mt-1">
            Ready-made 7-day meal plans with full USDA nutrition and a weekly grocery list —
            each one a real week you can copy straight to your own calendar.
          </p>
        </div>

        <div :if={@plans == []} class="text-center text-parchment-dim py-16">
          No meal plans have been published yet.
          <div class="mt-1 text-sm">
            <.link navigate={~p"/browse"} class="text-paprika hover:underline">
              Browse recipes instead
            </.link>
          </div>
        </div>

        <div class="pb-20 w-full grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <.meal_plan_card :for={plan <- @plans} plan={plan} from="meal_plans" />
        </div>
      </div>
    </div>
    """
  end

  # ── SEO ─────────────────────────────────────────────────────────────────────

  defp assign_seo(socket, plans) do
    socket
    |> assign(:page_title, "Weekly Meal Plans")
    |> assign(
      :page_description,
      "Browse ready-made 7-day meal plans with full USDA nutrition and weekly " <>
        "grocery lists. Copy any plan straight to your own calendar."
    )
    |> assign(:canonical_path, "/meal-plans")
    |> assign(:structured_data, structured_data(plans))
  end

  # CollectionPage + an ItemList of the published plans, each pointing at its own
  # indexable page — truthful nodes only (no fabricated ratings).
  defp structured_data(plans) do
    items =
      plans
      |> Enum.with_index(1)
      |> Enum.map(fn {plan, pos} ->
        %{
          "@type" => "ListItem",
          "position" => pos,
          "url" => @base_url <> "/meal-plans/" <> plan.slug,
          "name" => plan.title
        }
      end)

    breadcrumb = %{
      "@type" => "BreadcrumbList",
      "itemListElement" => [
        %{"@type" => "ListItem", "position" => 1, "name" => "Home", "item" => @base_url <> "/"},
        %{
          "@type" => "ListItem",
          "position" => 2,
          "name" => "Meal Plans",
          "item" => @base_url <> "/meal-plans"
        }
      ]
    }

    item_list = %{
      "@type" => "ItemList",
      "name" => "Weekly Meal Plans",
      "numberOfItems" => length(items),
      "itemListElement" => items
    }

    [breadcrumb, item_list]
  end
end
