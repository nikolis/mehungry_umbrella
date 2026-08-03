defmodule MehungryWeb.ProfessionalLive.SciencePipeline do
  @moduledoc """
  Unified control panel for the food-science pipeline. Runs the three operable
  stages in order — 1) literature crawl, 2) PubTator annotation, 4) candidate
  derivation — each with a Run button and a live progress bar, plus the candidate
  Promote/Reject review queue inline.

  The crawl reads each `FoundementalFoodSpecies`' curated `scientific_name`
  (set in the USDA Schema view), so there is no identity-resolution prerequisite.

  Each stage reuses an existing enqueue fn, `*_progress/0`, a runs module
  (`topic/0` + `latest_run/0`), and a PubSub broadcast tuple; this LiveView is
  pure web wiring over those seams. See `docs/scientific_pipeline.md`.
  """
  use MehungryWeb, :live_view

  alias Mehungry.Food
  alias Mehungry.Food.CandidateDerivationRuns
  alias Mehungry.Health.RecommendationCandidates
  alias Mehungry.Health.RecommendationDerivationRuns
  alias Mehungry.Literature
  alias Mehungry.Literature.AnnotationRuns
  alias Mehungry.Literature.CrawlRuns
  alias Mehungry.Science.PipelineReset

  @per_page 25

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, CrawlRuns.topic())
      Phoenix.PubSub.subscribe(Mehungry.PubSub, AnnotationRuns.topic())
      Phoenix.PubSub.subscribe(Mehungry.PubSub, CandidateDerivationRuns.topic())
      Phoenix.PubSub.subscribe(Mehungry.PubSub, RecommendationDerivationRuns.topic())
    end

    derivation_run = CandidateDerivationRuns.latest_run()
    recommendation_run = RecommendationDerivationRuns.latest_run()

    socket =
      socket
      |> assign(:page_title, "Science Pipeline")
      |> assign(:page, 1)
      |> assign(:crawl_run, CrawlRuns.latest_run())
      |> assign(:crawl_progress, normalize(Literature.crawl_progress()))
      |> assign(:annotation_run, AnnotationRuns.latest_run())
      |> assign(:annotation_progress, normalize(Literature.annotation_progress()))
      |> assign(:derivation_run, derivation_run)
      |> assign(:derivation_progress, derivation_progress(derivation_run))
      |> assign(:recommendation_run, recommendation_run)
      |> assign(:recommendation_progress, recommendation_progress(recommendation_run))
      |> assign_extraction()
      |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0))

    {:ok, socket}
  end

  # Full-text fetch + measurement extraction runs in the non-deployed
  # `mehungry_local_ai` service (GPU box) and posts results back over REST. Here we
  # only surface read-only status: studies still awaiting a fetch attempt, and the
  # count of pending measurement candidates waiting for review.
  defp assign_extraction(socket) do
    socket
    |> assign(:pmc_progress, normalize(Literature.pmc_fetch_progress()))
    |> assign(:mcand_count, Food.count_pending_measurement_candidates())
  end

  # ── Stage triggers ─────────────────────────────────────────────────────────

  @impl true
  def handle_event("run_crawl", _params, socket) do
    {:ok, run} = Literature.enqueue_crawl()

    {:noreply,
     socket
     |> assign(:crawl_run, run)
     |> put_flash(:info, "Crawl started — progress updates live below")}
  end

  @impl true
  def handle_event("run_annotation", _params, socket) do
    {:ok, run} = Literature.enqueue_annotation()

    {:noreply,
     socket
     |> assign(:annotation_run, run)
     |> put_flash(:info, "Annotation started — progress updates live below")}
  end

  @impl true
  def handle_event("derive", _params, socket) do
    {:ok, run} = Food.enqueue_candidate_derivation()

    {:noreply,
     socket
     |> assign(:derivation_run, run)
     |> put_flash(:info, "Derivation started — progress updates live below")}
  end

  @impl true
  def handle_event("derive_recommendations", _params, socket) do
    {:ok, run} = RecommendationCandidates.enqueue_recommendation_derivation()

    {:noreply,
     socket
     |> assign(:recommendation_run, run)
     |> put_flash(:info, "Recommendation derivation started — review candidates at Health conditions")}
  end

  # ── Candidate review ───────────────────────────────────────────────────────

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
    {:noreply, reload(socket)}
  end

  # ── Stage resets ───────────────────────────────────────────────────────────
  # Each clears its stage's generated data (crawl cascades to everything
  # downstream), then reloads every panel so the progress bars/labels drop back to
  # Idle · 0/0. Curated inputs are preserved — see `Science.PipelineReset`.

  @impl true
  def handle_event("reset_crawl", _params, socket) do
    counts = PipelineReset.reset_crawl()
    {:noreply, reload_with_flash(socket, "Crawl reset", counts)}
  end

  @impl true
  def handle_event("reset_annotation", _params, socket) do
    counts = PipelineReset.reset_annotation()
    {:noreply, reload_with_flash(socket, "Annotation reset", counts)}
  end

  @impl true
  def handle_event("reset_extraction", _params, socket) do
    counts = PipelineReset.reset_extraction()
    {:noreply, reload_with_flash(socket, "Extraction reset", counts)}
  end

  @impl true
  def handle_event("reset_derivation", _params, socket) do
    counts = PipelineReset.reset_derivation()
    {:noreply, reload_with_flash(socket, "Derivation reset", counts)}
  end

  @impl true
  def handle_event("reset_recommendations", _params, socket) do
    counts = PipelineReset.reset_recommendations()
    {:noreply, reload_with_flash(socket, "Recommendation derivation reset", counts)}
  end

  # Re-read every panel from scratch (shared by Refresh and all resets).
  defp reload(socket) do
    derivation_run = CandidateDerivationRuns.latest_run()

    socket
    |> assign(:page, 1)
    |> assign(:crawl_run, CrawlRuns.latest_run())
    |> assign(:crawl_progress, normalize(Literature.crawl_progress()))
    |> assign(:annotation_run, AnnotationRuns.latest_run())
    |> assign(:annotation_progress, normalize(Literature.annotation_progress()))
    |> assign(:derivation_run, derivation_run)
    |> assign(:derivation_progress, derivation_progress(derivation_run))
    |> assign(:recommendation_run, RecommendationDerivationRuns.latest_run())
    |> assign(
      :recommendation_progress,
      recommendation_progress(RecommendationDerivationRuns.latest_run())
    )
    |> assign_extraction()
    |> stream(:candidates, Food.list_pending_candidates(limit: @per_page, offset: 0), reset: true)
  end

  defp reload_with_flash(socket, label, counts) do
    total = counts |> Map.values() |> Enum.sum()

    detail =
      counts
      |> Enum.filter(fn {_t, n} -> n > 0 end)
      |> Enum.sort_by(fn {_t, n} -> -n end)
      |> Enum.map_join(", ", fn {t, n} -> "#{n} #{t}" end)

    message = if total == 0, do: "#{label} — nothing to clear", else: "#{label} — cleared #{total} rows (#{detail})"

    socket |> reload() |> put_flash(:info, message)
  end

  # ── Live run updates ───────────────────────────────────────────────────────
  # Broadcast by each stage's runs module as batches run. Progress-bar only; the
  # review stream is deliberately left untouched mid-run so rows don't shift under
  # a reviewer (they Refresh manually).

  @impl true
  def handle_info({:literature_crawl_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:crawl_run, run)
     |> assign(:crawl_progress, %{processed: run.processed || 0, total: run.total || 0})}
  end

  @impl true
  def handle_info({:pubtator_annotation_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:annotation_run, run)
     |> assign(:annotation_progress, %{processed: run.processed || 0, total: run.total || 0})}
  end

  @impl true
  def handle_info({:candidate_derivation_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:derivation_run, run)
     |> assign(:derivation_progress, %{processed: run.processed || 0, total: run.total || 0})}
  end

  @impl true
  def handle_info({:recommendation_derivation_run, run}, socket) do
    {:noreply,
     socket
     |> assign(:recommendation_run, run)
     |> assign(:recommendation_progress, %{processed: run.processed || 0, total: run.total || 0})}
  end

  # ── View helpers ───────────────────────────────────────────────────────────

  # All three stages report `%{processed, total}` already; kept as a single
  # pass-through so the progress-bar helpers have one shape to render.
  defp normalize(%{processed: _, total: _} = progress), do: progress

  defp derivation_progress(nil), do: normalize(Food.candidate_derivation_progress())
  defp derivation_progress(run), do: %{processed: run.processed || 0, total: run.total || 0}

  defp recommendation_progress(nil),
    do: normalize(RecommendationCandidates.recommendation_derivation_progress())

  defp recommendation_progress(run), do: %{processed: run.processed || 0, total: run.total || 0}

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{processed: processed, total: total}), do: round(processed / total * 100)

  defp running?(%{status: status}) when status in ["pending", "processing"], do: true
  defp running?(_), do: false

  defp run_label(nil), do: "Idle"
  defp run_label(%{status: "pending"}), do: "Queued…"
  defp run_label(%{status: "processing"}), do: "Running…"

  defp run_label(%{status: "completed"} = run) do
    case Map.get(run, :promoted_count) do
      nil -> "Completed"
      count -> "Completed · #{count} auto-promoted"
    end
  end

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
