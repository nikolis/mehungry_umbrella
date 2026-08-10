defmodule Mehungry.RecipePutNutrientsWorker do
  use Oban.Worker,
    max_attempts: 3

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.Recipe
  alias Mehungry.Food.NutrientRecalculationRuns

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    recipe_id = args["recipe_id"]
    # Present only for the tracked "recompute all" batch; nil for single-recipe
    # enqueues, in which case the NutrientRecalculationRuns.record_* calls no-op.
    run_id = args["run_id"]

    try do
      case recompute(recipe_id) do
        {:ok, recipe} ->
          NutrientRecalculationRuns.record_success(run_id)
          {:ok, recipe}

        {:error, reason} ->
          # Non-raising failure (missing recipe / invalid changeset). Count it
          # against the run and stop — retrying won't fix a deleted recipe.
          NutrientRecalculationRuns.record_failure(run_id, reason)
          :ok
      end
    rescue
      e ->
        cond do
          # Preserve the original single-recipe behaviour: let Oban retry/discard.
          is_nil(run_id) ->
            reraise e, __STACKTRACE__

          # Last attempt of a tracked job: count it so the run can complete,
          # rather than leaving the progress bar stuck below 100%.
          job.attempt >= job.max_attempts ->
            NutrientRecalculationRuns.record_failure(run_id, e)
            :ok

          true ->
            reraise e, __STACKTRACE__
        end
    end
  end

  defp recompute(recipe_id) do
    case Repo.get(Recipe, recipe_id) do
      nil ->
        {:error, :recipe_not_found}

      recipe ->
        recipe =
          Repo.preload(recipe, [
            [recipe_ingredients: [:measurement_unit, :ingredient]],
            :user,
            :recipe_hashtags,
            comments: [:user, votes: [:user], comment_answers: [:user, votes: [:user]]]
          ])

        changeset = Food.change_recipe(recipe)

        _create_post = Mehungry.Posts.create_post(recipe)

        Cachex.del(:recipes_cache, {Mehungry.Food, recipe_id})

        changeset
        |> Food.put_nutrient_info(Map.from_struct(recipe))
        |> Repo.update()
    end
  end
end
