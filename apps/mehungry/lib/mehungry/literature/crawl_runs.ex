defmodule Mehungry.Literature.CrawlRuns do
  @moduledoc """
  Lifecycle + progress tracking for literature-crawl passes.

  Mirrors `Mehungry.Food.IdentityResolutionRuns`: a single `CrawlRun` row carries
  a `processed`/`total` coverage snapshot refreshed each batch, transitions
  `pending → processing → completed` (or `failed`), and broadcasts every change on
  `Mehungry.PubSub` under `topic/0` so an admin view can render live progress.

  `update_status/2` is tolerant of a missing row (logs + no-ops) so a job whose
  run record was deleted mid-pass doesn't crash into pointless retries.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Literature
  alias Mehungry.Literature.CrawlRun, as: Run

  @topic "literature_crawl_runs"

  def topic, do: @topic

  @doc "Opens a run seeded with the current coverage snapshot and `started_at`."
  def start_run do
    %{processed: processed, total: total} = Literature.crawl_progress()

    {:ok, run} =
      %Run{}
      |> Run.changeset(%{
        status: "pending",
        processed: processed,
        total: total,
        studies_found: 0,
        error: nil,
        started_at: now(),
        completed_at: nil
      })
      |> Repo.insert(returning: true)

    broadcast(run)
    run
  end

  def mark_processing(run_id), do: update_status(run_id, %{status: "processing"})

  def update_progress(run_id, %{processed: processed, total: total}) do
    update_status(run_id, %{processed: processed, total: total})
  end

  def mark_completed(run_id, %{processed: processed, total: total}) do
    update_status(run_id, %{
      status: "completed",
      processed: processed,
      total: total,
      error: nil,
      completed_at: now()
    })
  end

  def mark_failed(run_id, reason) do
    update_status(run_id, %{status: "failed", error: inspect(reason)})
  end

  @doc "Most recent run, or nil."
  def latest_run do
    Repo.one(from(r in Run, order_by: [desc: r.inserted_at, desc: r.id], limit: 1))
  end

  # ── internals ────────────────────────────────────────────────────────────

  defp update_status(nil, _attrs), do: nil

  defp update_status(run_id, attrs) do
    case Repo.get(Run, run_id) do
      nil ->
        Logger.debug("Literature.CrawlRuns: run #{run_id} missing, skipping #{inspect(attrs)}")
        nil

      run ->
        updated = run |> Run.changeset(attrs) |> Repo.update!()
        broadcast(updated)
        updated
    end
  end

  defp broadcast(%Run{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:literature_crawl_run, run})
    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
