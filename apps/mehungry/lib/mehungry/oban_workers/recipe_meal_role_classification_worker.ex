defmodule Mehungry.ObanWorkers.RecipeMealRoleClassificationWorker do
  @moduledoc """
  Classifies recipes into meal roles (`Mehungry.Food.MealRoles`) with
  `RecipeMealRoleClassifier`. Two modes, one worker:

    * **Run batch** (`%{"run_id", "mode", "since"}`) — the admin backfill from
      `/professional/recipe-meal-roles`: classifies the next 20 pending recipes
      (`MealRoleAssignments.pending_classification_ids/2`), bumps the run's
      progress, and re-enqueues itself until nothing is pending. Same
      self-re-enqueueing shape as `TaxonomyClassificationWorker`; it always
      terminates because `apply_ai_roles/2` stamps every attempted recipe.
    * **Single recipe** (`%{"recipe_id"}`) — the save hook and the admin
      "Reclassify" button. Runs on `:default` (unique per recipe for 60 s, so a
      burst of edits folds into one call) and broadcasts the recipe update.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 3

  require Logger

  alias Mehungry.Food.{MealRoleAssignments, RecipeMealRoleRuns}

  @batch_size 20

  @doc "Enqueues a single-recipe classification (deduplicated per recipe for 60 s)."
  def enqueue_recipe(recipe_id) do
    %{"recipe_id" => recipe_id}
    |> new(
      queue: :default,
      unique: [period: 60, keys: [:recipe_id], states: [:available, :scheduled]]
    )
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"recipe_id" => recipe_id}}) do
    case classify_ids([recipe_id]) do
      {:ok, _} ->
        RecipeMealRoleRuns.broadcast_recipe_updated(recipe_id)
        :ok

      {:error, reason} ->
        Logger.warning(
          "RecipeMealRoleClassificationWorker: recipe #{recipe_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"run_id" => run_id, "mode" => mode} = args}) do
    RecipeMealRoleRuns.mark_processing(run_id)

    opts =
      case args["since"] do
        nil -> [limit: @batch_size]
        since -> [limit: @batch_size, since: parse_since(since)]
      end

    case MealRoleAssignments.pending_classification_ids(mode, opts) do
      [] ->
        RecipeMealRoleRuns.mark_completed(run_id)
        :ok

      ids ->
        case classify_ids(ids) do
          {:ok, processed} ->
            RecipeMealRoleRuns.add_processed(run_id, processed)

            %{"run_id" => run_id, "mode" => mode, "since" => args["since"]}
            |> new()
            |> Oban.insert!()

            :ok

          {:error, reason} ->
            Logger.warning("RecipeMealRoleClassificationWorker: batch failed: #{inspect(reason)}")
            RecipeMealRoleRuns.mark_failed(run_id, reason)
            {:error, reason}
        end
    end
  end

  # Classifies `ids` and writes every result (an id the model skipped is stamped
  # with an empty result so a run can't loop on it). `{:ok, attempted_count}`.
  defp classify_ids(ids) do
    inputs = MealRoleAssignments.classifier_inputs(ids)

    case classifier().classify(inputs) do
      {:ok, results} ->
        Enum.each(inputs, fn %{id: id} ->
          MealRoleAssignments.apply_ai_roles(id, Map.get(results, id, []))
        end)

        {:ok, length(inputs)}

      {:error, _} = error ->
        error
    end
  end

  defp parse_since(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp classifier do
    Application.get_env(:mehungry, :meal_role_classifier, Mehungry.AI.RecipeMealRoleClassifier)
  end
end
