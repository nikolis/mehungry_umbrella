defmodule MehungryWeb.ProfessionalLive.IngredientReconciliation do
  @moduledoc """
  Admin page to trigger and monitor the USDA ingredient reconciliation backfill
  (`data_type` from `food_class` + per-row `version` bump). Mirrors
  `ProfessionalLive.TaxonomyReview`: a batched, self-re-enqueueing Oban job plus
  a progress bar the admin refreshes to watch.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :progress, Food.reconciliation_progress())}
  end

  @impl true
  def handle_event("backfill", _params, socket) do
    Food.enqueue_ingredient_backfill()

    {:noreply,
     socket
     |> assign(:progress, Food.reconciliation_progress())
     |> put_flash(:info, "Backfill started — refresh to watch progress")}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, assign(socket, :progress, Food.reconciliation_progress())}
  end

  # ── View helpers ───────────────────────────────────────────────────────

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{done: done, total: total}), do: round(done / total * 100)
end
