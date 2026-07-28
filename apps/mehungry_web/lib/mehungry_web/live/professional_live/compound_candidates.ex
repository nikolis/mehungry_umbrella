defmodule MehungryWeb.ProfessionalLive.CompoundCandidates do
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.CandidateDerivationRuns

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, CandidateDerivationRuns.topic())
    end

    run = CandidateDerivationRuns.latest_run()

    socket =
      socket
      |> assign(:page_title, "Compound Candidates")
      |> assign(:page, 1)
      |> assign(:run, run)
      |> assign(:progress, progress_for(run))
      |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0))

    {:ok, socket}
  end

  # ── Triggers / review ──────────────────────────────────────────────────

  @impl true
  def handle_event("derive", _params, socket) do
    {:ok, run} = Food.enqueue_candidate_derivation()

    {:noreply,
     socket
     |> assign(:run, run)
     |> put_flash(:info, "Derivation started — progress updates live below")}
  end

  @impl true
  def handle_event("promote", %{"id" => id}, socket) do
    {:ok, _} = Food.promote_candidate(String.to_integer(id))
    {:noreply, stream_delete_by_dom_id(socket, :candidates, "candidates-#{id}")}
  end

  @impl true
  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} = Food.reject_candidate(String.to_integer(id))
    {:noreply, stream_delete_by_dom_id(socket, :candidates, "candidates-#{id}")}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    page = socket.assigns.page + 1
    offset = (page - 1) * @per_page

    {:noreply,
     socket
     |> assign(:page, page)
     |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: offset))}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    run = CandidateDerivationRuns.latest_run()

    {:noreply,
     socket
     |> assign(:page, 1)
     |> assign(:run, run)
     |> assign(:progress, progress_for(run))
     |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0), reset: true)}
  end

  # Live run broadcasts drive ONLY the progress bar; the review stream is left
  # untouched mid-run so rows don't shift under a reviewer (they Refresh manually).
  @impl true
  def handle_info({:candidate_derivation_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:run, run)
     |> assign(:progress, %{processed: run.processed || 0, total: run.total || 0})}
  end

  # ── View helpers ───────────────────────────────────────────────────────

  defp progress_for(nil), do: Food.candidate_derivation_progress()
  defp progress_for(run), do: %{processed: run.processed || 0, total: run.total || 0}

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{processed: processed, total: total}), do: round(processed / total * 100)

  defp running?(%{status: status}) when status in ["pending", "processing"], do: true
  defp running?(_), do: false

  defp run_label(nil), do: "Idle"
  defp run_label(%{status: "pending"}), do: "Queued…"
  defp run_label(%{status: "processing"}), do: "Deriving…"
  defp run_label(%{status: "completed"} = r), do: "Completed · #{r.promoted_count || 0} auto-promoted"
  defp run_label(%{status: "failed"}), do: "Failed"
  defp run_label(_), do: "Idle"

  defp run_class(%{status: "pending"}), do: "text-parchment-dim"
  defp run_class(%{status: "processing"}), do: "text-basil"
  defp run_class(%{status: "completed"}), do: "text-basil"
  defp run_class(%{status: "failed"}), do: "text-red-400"
  defp run_class(_), do: "text-parchment-dim"

  defp run_error(%{status: "failed", error: error}) when is_binary(error), do: error
  defp run_error(_), do: nil

  defp score_label(nil), do: "—"
  defp score_label(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 2)
  defp score_label(score), do: to_string(score)

  defp level_class("strong"), do: "text-basil"
  defp level_class("moderate"), do: "text-parchment"
  defp level_class("limited"), do: "text-parchment-dim"
  defp level_class(_), do: "text-parchment-dim"
end
