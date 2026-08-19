defmodule Mehungry.Food.HashtagReconciliations do
  @moduledoc """
  Query/command layer for `Mehungry.Food.HashtagReconciliation` — the durable
  tracking rows behind the admin hashtag-reconciliation sweep.

  Mirrors `Mehungry.FoodData.Usda.SeedFiles`. The terminal
  `pending → completed`/`failed` transitions each broadcast the full updated row
  (`{:hashtag_recon, %HashtagReconciliation{}}`) on `Mehungry.PubSub` under
  `topic/0`, so `MehungryWeb.ProfessionalLive.HashtagReconciliation` can patch
  that one row. The intermediate `processing` transition instead emits a
  deliberately lightweight `{:hashtag_recon_processing, recipe_id}` signal
  (identifier only) that the LiveView coalesces behind a flush timer — a
  full-corpus sweep fans out one job per recipe, so bounding the render cost of
  the high-frequency "in flight" hint matters. The row always moves on to a
  full-row `completed`/`failed` broadcast, so nothing is lost if a `processing`
  signal is dropped.
  """

  import Ecto.Query
  require Logger

  alias Mehungry.Food.{HashtagReconciliation, Recipe}
  alias Mehungry.Repo

  @topic "hashtag_reconciliation"

  @doc "PubSub topic carrying reconciliation row updates (single admin-only scope)."
  def topic, do: @topic

  @doc """
  Inserts a tracking row for `recipe_id`, or resets an existing one back to
  `pending` (clearing tags_added/error/completed_at). Idempotent. Returns the row.
  """
  def upsert_pending(recipe_id) do
    {:ok, reconciliation} =
      %HashtagReconciliation{}
      |> HashtagReconciliation.changeset(%{
        recipe_id: recipe_id,
        status: "pending",
        tags_added: nil,
        error: nil,
        completed_at: nil
      })
      |> Repo.insert(
        on_conflict: {:replace, [:status, :tags_added, :error, :completed_at, :updated_at]},
        conflict_target: [:recipe_id],
        returning: true
      )

    broadcast(reconciliation)
    reconciliation
  end

  # Marks the row processing (durable audit trail) and emits only the lightweight
  # coalesce-friendly `{:hashtag_recon_processing, recipe_id}` signal.
  def mark_processing(id) do
    case update_status(id, %{status: "processing"}, broadcast?: false) do
      %HashtagReconciliation{recipe_id: recipe_id} = reconciliation ->
        Phoenix.PubSub.broadcast(
          Mehungry.PubSub,
          @topic,
          {:hashtag_recon_processing, recipe_id}
        )

        reconciliation

      nil ->
        nil
    end
  end

  def mark_completed(id, tags_added) do
    update_status(id, %{
      status: "completed",
      tags_added: tags_added,
      error: nil,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def mark_failed(id, reason) do
    update_status(id, %{status: "failed", error: inspect(reason)})
  end

  @doc "All tracking rows, keyed by recipe_id for the UI."
  def list do
    HashtagReconciliation
    |> Repo.all()
    |> Map.new(fn r -> {r.recipe_id, r} end)
  end

  @doc """
  Display rows for the reconciliation LiveView: every recipe left-joined to its
  (optional) tracking row, so recipes never reconciled show a nil status.
  """
  def list_rows do
    from(r in Recipe,
      left_join: hr in HashtagReconciliation,
      on: hr.recipe_id == r.id,
      order_by: [asc: r.id],
      select: %{
        recipe_id: r.id,
        title: r.title,
        status: hr.status,
        tags_added: hr.tags_added,
        error: hr.error
      }
    )
    |> Repo.all()
  end

  @doc "All recipe ids (the unit-of-work universe for a full sweep)."
  def all_recipe_ids do
    Repo.all(from r in Recipe, select: r.id, order_by: [asc: r.id])
  end

  @doc """
  Aggregate tracking-row counts by status, e.g.
  `%{"pending" => 3, "processing" => 1, "completed" => 90, "failed" => 1}`.
  Cheap enough to re-query on a coalesced flush to drive a progress bar.
  """
  def counts do
    from(r in HashtagReconciliation, group_by: r.status, select: {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Deletes all tracking rows and cancels any still-pending reconciliation jobs so
  they don't run against deleted rows (see `update_status/2`, which no-ops on a
  missing row). Returns the number of rows deleted.
  """
  def reset do
    cancel_pending_jobs()
    {count, _} = Repo.delete_all(HashtagReconciliation)
    count
  end

  @doc """
  Filters `recipe_ids` down to those not yet `completed` — i.e. the set worth
  re-enqueuing. Ids with no row yet count as undone.
  """
  def pending_or_failed(recipe_ids) do
    completed =
      Repo.all(
        from r in HashtagReconciliation,
          where: r.recipe_id in ^recipe_ids and r.status == "completed",
          select: r.recipe_id
      )
      |> MapSet.new()

    Enum.reject(recipe_ids, &MapSet.member?(completed, &1))
  end

  defp cancel_pending_jobs do
    query =
      from(j in Oban.Job,
        where:
          j.queue == "hashtag_reconcile" and
            j.state in ["available", "scheduled", "retryable"]
      )

    Oban.cancel_all_jobs(query)
  end

  # Tolerant of a missing row: `reset/0` can delete tracking rows out from under
  # a running job, so a raise here would crash the job into pointless retries.
  defp update_status(id, attrs, opts \\ []) do
    case Repo.get(HashtagReconciliation, id) do
      nil ->
        Logger.info("[HashtagReconciliations] update_status skipped — row ##{id} no longer exists")
        nil

      reconciliation ->
        reconciliation =
          reconciliation
          |> HashtagReconciliation.changeset(attrs)
          |> Repo.update!()

        if Keyword.get(opts, :broadcast?, true), do: broadcast(reconciliation)
        reconciliation
    end
  end

  defp broadcast(%HashtagReconciliation{} = reconciliation) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:hashtag_recon, reconciliation})
    reconciliation
  end
end
