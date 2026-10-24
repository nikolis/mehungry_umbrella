defmodule Mehungry.FoodData.MyPlate.Imports do
  @moduledoc """
  Slug-keyed review tracking behind the manual MyPlate import flow
  (`MehungryWeb.CreateRecipeLive.Index` in `:myplate_review` mode).

  One `ImportRecord` row per reviewed slug records the outcome — `completed`
  (saved as a recipe) or `skipped` (passed on) — so the reviewer can resume
  through the ~1,072-recipe corpus across sessions. A slug with no row is
  unreviewed.
  """

  import Ecto.Query

  alias Mehungry.FoodData.MyPlate.ImportRecord
  alias Mehungry.Repo

  @doc "Records `slug` as reviewed-and-saved, pointing at the created `recipe_id`."
  def mark_completed(slug, recipe_id) do
    upsert(slug, %{
      status: "completed",
      recipe_id: recipe_id,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc "Records `slug` as skipped (\"pass for now\")."
  def mark_skipped(slug) do
    upsert(slug, %{status: "skipped", recipe_id: nil, completed_at: nil})
  end

  @doc "The review status of `slug` (`\"completed\"` | `\"skipped\"`), or `nil` if unreviewed."
  def status_for(slug) do
    Repo.one(from i in ImportRecord, where: i.slug == ^slug, select: i.status)
  end

  @doc "Set of every slug that has been reviewed (completed or skipped)."
  def reviewed_slugs do
    Repo.all(from i in ImportRecord, select: i.slug) |> MapSet.new()
  end

  @doc """
  Map of `slug => status` for every reviewed slug, e.g.
  `%{"ambrosia" => "completed"}`. Powers the status badges in the searchable
  recipe list; a slug absent from the map is unreviewed.
  """
  def statuses_by_slug do
    from(i in ImportRecord, select: {i.slug, i.status})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Review counts by status, e.g. `%{\"completed\" => 12, \"skipped\" => 3}`."
  def counts do
    from(i in ImportRecord, group_by: i.status, select: {i.status, count(i.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Clears all review tracking. Returns the number of rows deleted."
  def reset do
    {count, _} = Repo.delete_all(ImportRecord)
    count
  end

  # Insert a row for `slug`, or update it in place (idempotent re-review).
  defp upsert(slug, attrs) do
    {:ok, record} =
      %ImportRecord{}
      |> ImportRecord.changeset(Map.put(attrs, :slug, slug))
      |> Repo.insert(
        on_conflict: {:replace, [:status, :recipe_id, :completed_at, :updated_at]},
        conflict_target: [:slug],
        returning: true
      )

    record
  end
end
