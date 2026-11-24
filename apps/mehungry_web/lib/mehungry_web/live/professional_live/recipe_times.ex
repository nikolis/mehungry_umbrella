defmodule MehungryWeb.ProfessionalLive.RecipeTimes do
  @moduledoc """
  Admin page for recipe prep/cook **time coverage** and its AI backfill
  (`Mehungry.Food.RecipeTimeEstimation`). The AI meal planner's breakfast (≤ 15 min)
  and dinner (≤ 40 min) rules skip a recipe with no time, so this page shows how many
  are missing and starts an "Estimate missing times" run with live progress (the
  Oban-UI-connected pattern).
  """

  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.RecipeTimeEstimation

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket),
      do: Phoenix.PubSub.subscribe(Mehungry.PubSub, RecipeTimeEstimation.topic())

    {:ok,
     socket
     |> assign(:page_title, "Recipe times")
     |> assign(:run, RecipeTimeEstimation.latest_run())
     |> assign(:coverage, Food.recipe_time_coverage())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto p-4 space-y-6">
      <div>
        <h1 class="text-2xl font-semibold text-parchment">Recipe times</h1>
        <p class="text-sm text-parchment-dim mt-1">
          The AI meal planner only offers a recipe for Breakfast (≤ 15 min) or a weeknight
          Dinner (≤ 40 min) when its prep + cook time is known. Recipes saved without a time
          can be estimated by AI here; only empty fields are filled, never a time someone typed.
        </p>
      </div>

      <section
        id="time-coverage"
        class="grid grid-cols-2 md:grid-cols-4 gap-3 rounded-lg border border-ink-panel2 bg-ink-panel p-4"
      >
        <.stat label="Recipes" value={@coverage.total} />
        <.stat label="With a time" value={@coverage.with_time} />
        <.stat id="missing-count" label="Missing a time" value={@coverage.missing} />
        <.stat label="AI could not time" value={@coverage.attempted_without} />
      </section>

      <section class="space-y-3 rounded-lg border border-ink-panel2 bg-ink-panel p-4">
        <button
          id="estimate-times"
          type="button"
          phx-click="estimate"
          disabled={RecipeTimeEstimation.running?(@run) or @coverage.missing == 0}
          class="px-4 py-2 rounded bg-paprika text-ink text-sm font-semibold disabled:opacity-50"
        >
          Estimate missing times ({@coverage.missing})
        </button>

        <div :if={@run} id="time-run" class="text-sm text-parchment-dim space-y-1">
          <div>
            Last run: <span class="text-parchment font-medium">{@run.status}</span>
            — {@run.processed} / {@run.total}
          </div>
          <div class="h-2 rounded bg-ink-panel2 overflow-hidden">
            <div class="h-2 bg-basil" style={"width: #{pct(@run)}%"}></div>
          </div>
          <div :if={@run.error} class="text-paprika">{@run.error}</div>
        </div>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :id, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div id={@id}>
      <div class="text-2xl font-semibold text-parchment [font-variant-numeric:tabular-nums]">
        {@value}
      </div>
      <div class="text-xs text-parchment-dim">{@label}</div>
    </div>
    """
  end

  defp pct(%{total: total, processed: processed}) when total > 0,
    do: min(100, round(processed * 100 / total))

  defp pct(_run), do: 0

  @impl true
  def handle_event("estimate", _params, socket) do
    case Food.enqueue_recipe_time_estimation() do
      {:ok, run} ->
        {:noreply, assign(socket, :run, run)}

      {:error, :already_running} ->
        {:noreply, put_flash(socket, :error, "A run is already in progress.")}

      {:error, :nothing_pending} ->
        {:noreply, put_flash(socket, :info, "Every recipe already has a time.")}
    end
  end

  @impl true
  def handle_info({:recipe_time_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:run, run)
     |> assign(:coverage, Food.recipe_time_coverage())}
  end
end
