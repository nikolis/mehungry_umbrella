defmodule Mehungry.Food.RecipeMealRoleRuns do
  @moduledoc """
  Query/command layer for `Mehungry.Food.RecipeMealRoleRun` — the durable rows
  behind a meal-role classification run. Every transition broadcasts
  `{:meal_role_run, run}` on `topic/0` so
  `MehungryWeb.ProfessionalLive.RecipeMealRoles` renders a live progress bar.
  Mirrors `Mehungry.Food.TaxonomyClassificationRuns`.

  The same topic also carries `{:recipe_meal_roles_updated, recipe_id}` after a
  single recipe is (re)classified, so the admin page can refresh that row.
  """

  import Ecto.Query
  require Logger

  alias Mehungry.Food.RecipeMealRoleRun
  alias Mehungry.Repo

  @topic "recipe_meal_roles"

  @doc "PubSub topic for run progress and per-recipe updates."
  def topic, do: @topic

  @doc "Inserts a `pending` run for `mode` with its starting `total`; broadcasts it."
  def start_run(mode, total) do
    {:ok, run} =
      %RecipeMealRoleRun{}
      |> RecipeMealRoleRun.changeset(%{
        mode: mode,
        status: "pending",
        processed: 0,
        total: total,
        started_at: now()
      })
      |> Repo.insert(returning: true)

    broadcast(run)
  end

  def get_run(nil), do: nil
  def get_run(id), do: Repo.get(RecipeMealRoleRun, id)

  def mark_processing(run_id), do: update_status(run_id, %{status: "processing"})

  @doc "Atomically adds `n` to `processed`, then broadcasts the fresh row."
  def add_processed(nil, _n), do: nil

  def add_processed(run_id, n) do
    from(r in RecipeMealRoleRun, where: r.id == ^run_id)
    |> Repo.update_all(inc: [processed: n], set: [updated_at: NaiveDateTime.utc_now(:second)])

    case get_run(run_id) do
      nil -> nil
      run -> broadcast(run)
    end
  end

  def mark_completed(run_id),
    do: update_status(run_id, %{status: "completed", error: nil, completed_at: now()})

  def mark_failed(run_id, reason),
    do: update_status(run_id, %{status: "failed", error: inspect(reason), completed_at: now()})

  @doc "The most recent run, or nil."
  def latest_run do
    Repo.one(from r in RecipeMealRoleRun, order_by: [desc: r.id], limit: 1)
  end

  @doc "True while a run is pending or processing."
  def running?(%RecipeMealRoleRun{status: status}) when status in ["pending", "processing"],
    do: true

  def running?(_), do: false

  @doc "Broadcasts that one recipe's roles changed (e.g. after a single reclassify)."
  def broadcast_recipe_updated(recipe_id) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:recipe_meal_roles_updated, recipe_id})
  end

  # Tolerant of a missing row, like TaxonomyClassificationRuns.update_status/2.
  defp update_status(nil, _attrs), do: nil

  defp update_status(run_id, attrs) do
    case Repo.get(RecipeMealRoleRun, run_id) do
      nil ->
        Logger.info("[RecipeMealRoleRuns] update skipped — run ##{run_id} is gone")
        nil

      run ->
        run
        |> RecipeMealRoleRun.changeset(attrs)
        |> Repo.update!()
        |> broadcast()
    end
  end

  defp broadcast(%RecipeMealRoleRun{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:meal_role_run, run})
    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
