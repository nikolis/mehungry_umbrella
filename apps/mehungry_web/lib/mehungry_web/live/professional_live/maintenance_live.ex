defmodule MehungryWeb.ProfessionalLive.MaintenanceLive do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:recipe_count, Food.count_recipes())
     |> assign(:job_status, nil)
     |> assign(:enqueued_count, nil)
     |> assign(:running, false)
     |> assign(:interactions_job_status, nil)
     |> assign(:interactions_enqueued_count, nil)
     |> assign(:interactions_running, false)}
  end

  @impl true
  def handle_event("recalculate_all_nutrients", _params, socket) do
    count = Food.enqueue_nutrient_recalculation_for_all()

    {:noreply,
     socket
     |> assign(:running, true)
     |> assign(:enqueued_count, count)
     |> assign(:job_status, :enqueued)
     |> put_flash(:info, "Enqueued nutrient recalculation for #{count} recipes.")}
  end

  @impl true
  def handle_event("recalculate_all_interactions", _params, socket) do
    count = Food.enqueue_interaction_recalculation_for_all()

    {:noreply,
     socket
     |> assign(:interactions_running, true)
     |> assign(:interactions_enqueued_count, count)
     |> assign(:interactions_job_status, :enqueued)
     |> put_flash(:info, "Enqueued interaction recalculation for #{count} recipes.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-6 sm:px-6 lg:px-8 max-w-5xl mx-auto space-y-6">
      <div>
        <h1 class="text-2xl font-bold text-white">Maintenance</h1>
        <p class="text-slate-400 text-sm mt-0.5">Admin operations and data repair tools</p>
      </div>

      <!-- Nutrient Recalculation -->
      <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-white">Recalculate Recipe Nutrients</h2>
            <p class="text-slate-400 text-sm mt-1 max-w-lg">
              Re-runs the nutrient calculation pipeline for every recipe in the database.
              Each recipe is enqueued as an Oban job and processed in the background.
              Use this after fixing a calculation bug (e.g. the energy deduplication fix)
              to backfill correct values for existing recipes.
            </p>
            <div class="mt-3 flex items-center gap-3 text-sm text-slate-400">
              <span class="inline-flex items-center gap-1.5">
                <svg class="w-4 h-4 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                </svg>
                <span><strong class="text-white">{@recipe_count}</strong> recipes in DB</span>
              </span>
              <%= if @enqueued_count do %>
                <span class="inline-flex items-center gap-1.5 text-emerald-400">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                  <span><strong>{@enqueued_count}</strong> jobs enqueued</span>
                </span>
              <% end %>
            </div>
          </div>

          <button
            phx-click="recalculate_all_nutrients"
            data-confirm={"Re-run nutrient calculations for all #{@recipe_count} recipes? This will enqueue #{@recipe_count} background jobs."}
            class={[
              "flex-shrink-0 inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold transition",
              if(@running,
                do: "bg-slate-700 text-slate-400 cursor-not-allowed",
                else: "bg-primary-500 hover:bg-primary-600 text-white"
              )
            ]}
            disabled={@running}
          >
            <svg class={["w-4 h-4", if(@running, do: "animate-spin")]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            <%= if @running, do: "Jobs enqueued", else: "Recalculate all" %>
          </button>
        </div>

        <%= if @job_status == :enqueued do %>
          <div class="mt-4 p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-sm">
            <strong>{@enqueued_count} Oban jobs</strong> have been enqueued.
            Processing happens in the background — check the Oban dashboard or server logs for progress.
            Each job recalculates and saves nutrients for one recipe.
          </div>
        <% end %>
      </div>

      <!-- Ingredient Interaction Backfill -->
      <div class="bg-slate-800 border border-slate-700 rounded-2xl p-6">
        <div class="flex items-start justify-between gap-4">
          <div>
            <h2 class="text-lg font-semibold text-white">Backfill Ingredient Interactions</h2>
            <p class="text-slate-400 text-sm mt-1 max-w-lg">
              Re-computes stored nutrient interaction badges for every recipe.
              Interactions are derived from the recipe's existing nutrient data — no ingredient
              DB queries are needed. Use this after updating interaction rules or after running
              a nutrient recalculation to propagate fresh results.
            </p>
            <div class="mt-3 flex items-center gap-3 text-sm text-slate-400">
              <span class="inline-flex items-center gap-1.5">
                <svg class="w-4 h-4 text-primary-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                    d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
                </svg>
                <span><strong class="text-white">{@recipe_count}</strong> recipes in DB</span>
              </span>
              <%= if @interactions_enqueued_count do %>
                <span class="inline-flex items-center gap-1.5 text-emerald-400">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
                  </svg>
                  <span><strong>{@interactions_enqueued_count}</strong> jobs enqueued</span>
                </span>
              <% end %>
            </div>
          </div>

          <button
            phx-click="recalculate_all_interactions"
            data-confirm={"Backfill ingredient interactions for all #{@recipe_count} recipes? This will enqueue #{@recipe_count} background jobs."}
            class={[
              "flex-shrink-0 inline-flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-semibold transition",
              if(@interactions_running,
                do: "bg-slate-700 text-slate-400 cursor-not-allowed",
                else: "bg-primary-500 hover:bg-primary-600 text-white"
              )
            ]}
            disabled={@interactions_running}
          >
            <svg class={["w-4 h-4", if(@interactions_running, do: "animate-spin")]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
                d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            <%= if @interactions_running, do: "Jobs enqueued", else: "Backfill all" %>
          </button>
        </div>

        <%= if @interactions_job_status == :enqueued do %>
          <div class="mt-4 p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-sm">
            <strong>{@interactions_enqueued_count} Oban jobs</strong> have been enqueued.
            Processing happens in the background — check server logs for progress.
            Each job recomputes interactions from the recipe's stored nutrient data and saves the result.
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
