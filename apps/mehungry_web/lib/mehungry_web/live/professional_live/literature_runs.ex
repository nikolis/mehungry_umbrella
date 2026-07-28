defmodule MehungryWeb.ProfessionalLive.LiteratureRuns do
  use MehungryWeb, :live_view

  alias Mehungry.Literature
  alias Mehungry.Literature.AnnotationRuns
  alias Mehungry.Literature.CrawlRuns

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mehungry.PubSub, CrawlRuns.topic())
      Phoenix.PubSub.subscribe(Mehungry.PubSub, AnnotationRuns.topic())
    end

    socket =
      socket
      |> assign(:page_title, "Literature")
      |> assign(:crawl_progress, Literature.crawl_progress())
      |> assign(:crawl_run, CrawlRuns.latest_run())
      |> assign(:annotation_progress, Literature.annotation_progress())
      |> assign(:annotation_run, AnnotationRuns.latest_run())

    {:ok, socket}
  end

  # ── Triggers ───────────────────────────────────────────────────────────

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
  def handle_event("refresh", _params, socket) do
    {:noreply,
     socket
     |> assign(:crawl_progress, Literature.crawl_progress())
     |> assign(:crawl_run, CrawlRuns.latest_run())
     |> assign(:annotation_progress, Literature.annotation_progress())
     |> assign(:annotation_run, AnnotationRuns.latest_run())}
  end

  # ── Live run updates ───────────────────────────────────────────────────
  # Broadcast by CrawlRuns / AnnotationRuns as batches run. Progress-bar only.

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

  # ── View helpers ───────────────────────────────────────────────────────

  defp percent(%{total: total}) when total in [0, nil], do: 0
  defp percent(%{processed: processed, total: total}), do: round(processed / total * 100)

  defp running?(%{status: status}) when status in ["pending", "processing"], do: true
  defp running?(_), do: false

  defp run_label(nil), do: "Idle"
  defp run_label(%{status: "pending"}), do: "Queued…"
  defp run_label(%{status: "processing"}), do: "Running…"
  defp run_label(%{status: "completed"}), do: "Completed"
  defp run_label(%{status: "failed"}), do: "Failed"
  defp run_label(_), do: "Idle"

  defp run_class(%{status: "pending"}), do: "text-parchment-dim"
  defp run_class(%{status: "processing"}), do: "text-basil"
  defp run_class(%{status: "completed"}), do: "text-basil"
  defp run_class(%{status: "failed"}), do: "text-red-400"
  defp run_class(_), do: "text-parchment-dim"

  defp run_error(%{status: "failed", error: error}) when is_binary(error), do: error
  defp run_error(_), do: nil
end
