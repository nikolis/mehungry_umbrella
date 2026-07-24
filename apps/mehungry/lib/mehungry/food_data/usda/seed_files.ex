defmodule Mehungry.FoodData.Usda.SeedFiles do
  @moduledoc """
  Query/command layer for `Mehungry.FoodData.Usda.SeedFile` — the durable
  tracking rows behind the S3 ingredient-seeding flow.

  Every status transition broadcasts the updated row on `Mehungry.PubSub` under
  `topic(bucket)`, so `MehungryWeb.ProfessionalLive.S3BrowserLive` can render
  live progress and offer per-file re-do controls.
  """

  import Ecto.Query

  alias Mehungry.FoodData.Usda.SeedFile
  alias Mehungry.Repo

  @doc "PubSub topic carrying `{:seed_file, %SeedFile{}}` updates for a bucket."
  def topic(bucket), do: "seed_files:#{bucket}"

  @doc """
  Inserts a tracking row for `{bucket, key}`, or resets an existing one back to
  `pending` (clearing count/error/completed_at). Idempotent — used both when
  first enqueuing a bucket and when re-doing an undone file. Returns the row.
  """
  def upsert_pending(bucket, key) do
    {:ok, seed_file} =
      %SeedFile{}
      |> SeedFile.changeset(%{
        bucket: bucket,
        key: key,
        status: "pending",
        ingredient_count: nil,
        error: nil,
        completed_at: nil
      })
      |> Repo.insert(
        on_conflict: {:replace, [:status, :ingredient_count, :error, :completed_at, :updated_at]},
        conflict_target: [:bucket, :key],
        returning: true
      )

    broadcast(seed_file)
    seed_file
  end

  def mark_processing(id), do: update_status(id, %{status: "processing"})

  def mark_completed(id, count) do
    update_status(id, %{
      status: "completed",
      ingredient_count: count,
      error: nil,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def mark_failed(id, reason) do
    update_status(id, %{status: "failed", error: inspect(reason)})
  end

  @doc "All tracking rows for a bucket/prefix, keyed by object key for the UI."
  def list_by_bucket(bucket, prefix \\ nil) do
    query = from(s in SeedFile, where: s.bucket == ^bucket)

    query =
      if prefix in [nil, ""] do
        query
      else
        pattern = escape_like(prefix) <> "%"
        from(s in query, where: like(s.key, ^pattern))
      end

    query
    |> Repo.all()
    |> Map.new(fn s -> {s.key, s} end)
  end

  @doc """
  Filters `keys` down to those not yet `completed` for this bucket — i.e. the
  set worth re-enqueuing. Keys with no row yet count as undone.
  """
  def pending_or_failed(bucket, keys) do
    completed =
      Repo.all(
        from s in SeedFile,
          where: s.bucket == ^bucket and s.key in ^keys and s.status == "completed",
          select: s.key
      )
      |> MapSet.new()

    Enum.reject(keys, &MapSet.member?(completed, &1))
  end

  defp update_status(id, attrs) do
    seed_file =
      Repo.get!(SeedFile, id)
      |> SeedFile.changeset(attrs)
      |> Repo.update!()

    broadcast(seed_file)
    seed_file
  end

  defp broadcast(%SeedFile{} = seed_file) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, topic(seed_file.bucket), {:seed_file, seed_file})
    seed_file
  end

  defp escape_like(value) do
    String.replace(value, ~r/([\\%_])/, "\\\\\\1")
  end
end
