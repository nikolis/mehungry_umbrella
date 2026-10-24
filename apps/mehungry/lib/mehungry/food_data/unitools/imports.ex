defmodule Mehungry.FoodData.UniTools.Imports do
  @moduledoc """
  Ref-keyed review tracking behind the manual UniTools import flow
  (`MehungryWeb.ProfessionalLive.UniToolsReview`).

  One `ImportRecord` row per reviewed recipe ref (`"<dataset_id>:<index>"`)
  records the outcome — `completed` (saved as a recipe) or `skipped` (passed on)
  — so the reviewer can resume across sessions and per dataset. A ref with no row
  is unreviewed. Mirrors `Mehungry.FoodData.Gutenberg.Imports`.
  """

  import Ecto.Query

  alias Mehungry.FoodData.UniTools.ImportRecord
  alias Mehungry.Repo

  @doc "Builds the ref (`\"<dataset_id>:<index>\"`) for a recipe `index` in `dataset_id`."
  def ref(dataset_id, index), do: "#{dataset_id}:#{index}"

  @doc "Records `ref` as reviewed-and-saved, pointing at the created `recipe_id`."
  def mark_completed(ref, recipe_id) do
    upsert(ref, %{
      status: "completed",
      recipe_id: recipe_id,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  @doc "Records `ref` as skipped (\"pass for now\")."
  def mark_skipped(ref) do
    upsert(ref, %{status: "skipped", recipe_id: nil, completed_at: nil})
  end

  @doc "The review status of `ref` (`\"completed\"` | `\"skipped\"`), or `nil` if unreviewed."
  def status_for(ref) do
    Repo.one(from i in ImportRecord, where: i.ref == ^ref, select: i.status)
  end

  @doc "Set of every ref reviewed (completed or skipped) for `dataset_id`."
  def reviewed_refs(dataset_id) do
    prefix = "#{dataset_id}:%"

    Repo.all(from i in ImportRecord, where: like(i.ref, ^prefix), select: i.ref)
    |> MapSet.new()
  end

  @doc """
  Map of `recipe_index => status` for `dataset_id`, e.g. `%{1 => "completed"}`.
  Powers the status badges in the searchable recipe list; an index absent from
  the map is unreviewed.
  """
  def statuses_for(dataset_id) do
    prefix = "#{dataset_id}:%"

    from(i in ImportRecord, where: like(i.ref, ^prefix), select: {i.ref, i.status})
    |> Repo.all()
    |> Map.new(fn {ref, status} -> {index_from_ref(ref), status} end)
  end

  defp index_from_ref(ref) do
    ref |> String.split(":", parts: 2) |> List.last() |> String.to_integer()
  end

  @doc """
  Review counts grouped by dataset id, e.g.
  `%{"v1" => %{"completed" => 12, "skipped" => 3}}`.
  """
  def counts_by_dataset do
    from(i in ImportRecord, select: {i.ref, i.status})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {ref, status}, acc ->
      dataset_id = ref |> String.split(":", parts: 2) |> hd()

      acc
      |> Map.put_new(dataset_id, %{})
      |> update_in([dataset_id, status], &((&1 || 0) + 1))
    end)
  end

  @doc "Clears all review tracking. Returns the number of rows deleted."
  def reset do
    {count, _} = Repo.delete_all(ImportRecord)
    count
  end

  # Insert a row for `ref`, or update it in place (idempotent re-review).
  defp upsert(ref, attrs) do
    {:ok, record} =
      %ImportRecord{}
      |> ImportRecord.changeset(Map.put(attrs, :ref, ref))
      |> Repo.insert(
        on_conflict: {:replace, [:status, :recipe_id, :completed_at, :updated_at]},
        conflict_target: [:ref],
        returning: true
      )

    record
  end
end
