defmodule Mehungry.Food.RecipeTimeEstimation do
  @moduledoc """
  AI backfill of missing recipe **prep / cook times**.

  The meal planner's time rules (breakfast ≤ 15 min, dinner ≤ 40 min — see
  `Food.total_time_minutes/1`) exclude a recipe whose time is unknown, so recipes
  without one are effectively invisible to those slots. This module fills them:

    * **Pending** = no time at all (prep and cook both empty/zero) and never
      attempted (`times_estimated_at` is nil). An attempted recipe is stamped even
      when the model returned nothing, so a run always terminates.
    * **Only empty fields are written** — a human-entered prep or cook time is
      never overwritten.
    * Runs follow the Oban-UI-connected pattern
      (`docs/reference_architecture/oban_ui_connected_worker.md`): a durable
      `RecipeTimeEstimationRun`, the self-re-enqueueing
      `RecipeTimeEstimationWorker` on `:ai_agents`, and `{:recipe_time_run, run}`
      broadcasts on `topic/0` for `/professional/recipe-times`.
  """

  import Ecto.Query
  require Logger

  alias Mehungry.Food.{Recipe, RecipeTimeEstimationRun}
  alias Mehungry.ObanWorkers.RecipeTimeEstimationWorker
  alias Mehungry.Repo

  @topic "recipe_time_estimation"

  # Sanity bounds on what an estimate may write (minutes).
  @max_minutes 24 * 60

  def topic, do: @topic

  # ── coverage + pending ───────────────────────────────────────────────────────

  @doc """
  Time coverage of the catalogue: `%{total, with_time, missing, attempted_without}`
  — `attempted_without` are recipes the estimator tried but could not time.
  """
  def coverage do
    Repo.one(
      from r in Recipe,
        select: %{
          total: count(r.id),
          with_time:
            fragment(
              "count(*) FILTER (WHERE COALESCE(?, 0) + COALESCE(?, 0) > 0)",
              r.preperation_time_lower_limit,
              r.cooking_time_lower_limit
            ),
          missing:
            fragment(
              "count(*) FILTER (WHERE COALESCE(?, 0) + COALESCE(?, 0) = 0 AND ? IS NULL)",
              r.preperation_time_lower_limit,
              r.cooking_time_lower_limit,
              r.times_estimated_at
            ),
          attempted_without:
            fragment(
              "count(*) FILTER (WHERE COALESCE(?, 0) + COALESCE(?, 0) = 0 AND ? IS NOT NULL)",
              r.preperation_time_lower_limit,
              r.cooking_time_lower_limit,
              r.times_estimated_at
            )
        }
    )
  end

  @doc "Ids of pending recipes (no time, never attempted), oldest first."
  def pending_ids(opts \\ []) do
    query =
      from r in Recipe,
        where: is_nil(r.times_estimated_at),
        where:
          coalesce(r.preperation_time_lower_limit, 0) + coalesce(r.cooking_time_lower_limit, 0) ==
            0,
        order_by: r.id,
        select: r.id

    query = if limit = opts[:limit], do: limit(query, ^limit), else: query
    Repo.all(query)
  end

  # ── estimator inputs + writes ────────────────────────────────────────────────

  @doc "What the estimator sees for each recipe: title, servings, ingredients, steps."
  def estimator_inputs(ids) do
    from(r in Recipe, where: r.id in ^ids, order_by: r.id)
    |> Repo.all()
    |> Repo.preload(recipe_ingredients: :ingredient)
    |> Enum.map(fn r ->
      %{
        id: r.id,
        title: r.title,
        servings: r.servings,
        ingredients:
          r.recipe_ingredients
          |> Enum.map(&(&1.ingredient && &1.ingredient.name))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> Enum.take(15),
        steps:
          (r.steps || [])
          |> Enum.sort_by(&(&1.index || 0))
          |> Enum.map(&truncate(&1.description, 200))
          |> Enum.take(12)
      }
    end)
  end

  @doc """
  Applies one estimate (`%{prep: int | nil, cook: int | nil}`, minutes) to a
  recipe: fills only the fields that are empty, and always stamps
  `times_estimated_at`. Returns `:ok`.
  """
  def apply_estimate(recipe_id, estimate) do
    case Repo.get(Recipe, recipe_id) do
      nil ->
        :ok

      recipe ->
        set =
          [times_estimated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
          |> fill(:preperation_time_lower_limit, recipe, minutes(estimate[:prep]))
          |> fill(:cooking_time_lower_limit, recipe, minutes(estimate[:cook]))

        from(r in Recipe, where: r.id == ^recipe_id) |> Repo.update_all(set: set)
        # get_recipe!/1 caches the struct the recipe page renders.
        Cachex.del(:recipes_cache, {Mehungry.Food, recipe_id})
        :ok
    end
  end

  defp fill(set, field, recipe, value) do
    current = Map.get(recipe, field)

    if (is_nil(current) or current == 0) and is_integer(value),
      do: Keyword.put(set, field, value),
      else: set
  end

  defp minutes(n) when is_integer(n) and n >= 0 and n <= @max_minutes, do: n
  defp minutes(n) when is_float(n), do: minutes(round(n))
  defp minutes(_), do: nil

  # ── runs ─────────────────────────────────────────────────────────────────────

  @doc """
  Starts a tracked "Estimate missing times" run and enqueues its first batch.
  `{:ok, run}`, `{:error, :already_running}` or `{:error, :nothing_pending}`.
  """
  def enqueue_estimation do
    total = if running?(latest_run()), do: :running, else: length(pending_ids())

    case total do
      :running ->
        {:error, :already_running}

      0 ->
        {:error, :nothing_pending}

      total ->
        {:ok, run} =
          %RecipeTimeEstimationRun{}
          |> RecipeTimeEstimationRun.changeset(%{
            status: "pending",
            total: total,
            started_at: now()
          })
          |> Repo.insert()

        {:ok, _job} = %{"run_id" => run.id} |> RecipeTimeEstimationWorker.new() |> Oban.insert()
        {:ok, broadcast(run)}
    end
  end

  def latest_run do
    Repo.one(from r in RecipeTimeEstimationRun, order_by: [desc: r.id], limit: 1)
  end

  def get_run(id), do: Repo.get(RecipeTimeEstimationRun, id)

  def running?(%RecipeTimeEstimationRun{status: s}) when s in ["pending", "processing"], do: true
  def running?(_), do: false

  def mark_processing(run_id), do: update_run(run_id, %{status: "processing"})
  def mark_completed(run_id), do: update_run(run_id, %{status: "completed", completed_at: now()})

  def mark_failed(run_id, reason),
    do: update_run(run_id, %{status: "failed", error: inspect(reason), completed_at: now()})

  @doc "Atomically adds `n` to `processed`, then broadcasts the fresh row."
  def add_processed(run_id, n) do
    from(r in RecipeTimeEstimationRun, where: r.id == ^run_id)
    |> Repo.update_all(inc: [processed: n], set: [updated_at: NaiveDateTime.utc_now(:second)])

    case get_run(run_id) do
      nil -> nil
      run -> broadcast(run)
    end
  end

  defp update_run(run_id, attrs) do
    case get_run(run_id) do
      nil ->
        Logger.info("[RecipeTimeEstimation] update skipped — run ##{run_id} is gone")
        nil

      run ->
        run |> RecipeTimeEstimationRun.changeset(attrs) |> Repo.update!() |> broadcast()
    end
  end

  defp broadcast(run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:recipe_time_run, run})
    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp truncate(nil, _), do: nil
  defp truncate(text, max) when byte_size(text) <= max, do: text
  defp truncate(text, max), do: String.slice(text, 0, max) <> "…"
end
