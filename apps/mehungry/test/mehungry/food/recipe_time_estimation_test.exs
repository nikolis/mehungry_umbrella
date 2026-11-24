defmodule Mehungry.Food.RecipeTimeEstimationTest do
  # Swaps the estimator stub through app config — not async.
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.Food
  alias Mehungry.Food.{Recipe, RecipeTimeEstimation}
  alias Mehungry.ObanWorkers.RecipeTimeEstimationWorker
  alias Mehungry.Repo

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :recipe_time_estimator_stub) end)
    user = user_fixture()

    %{
      timed: timed(recipe_fixture(user, %{title: "Timed"}), 10, 20),
      prep_only: timed(recipe_fixture(user, %{title: "Prep only"}), 5, nil),
      untimed: timed(recipe_fixture(user, %{title: "Untimed omelette"}), nil, nil),
      untimed2: timed(recipe_fixture(user, %{title: "Untimed stew"}), nil, nil)
    }
  end

  defp timed(recipe, prep, cook) do
    Repo.update_all(from(r in Recipe, where: r.id == ^recipe.id),
      set: [preperation_time_lower_limit: prep, cooking_time_lower_limit: cook]
    )

    Repo.get!(Recipe, recipe.id)
  end

  defp stub(fun), do: Application.put_env(:mehungry, :recipe_time_estimator_stub, fun)

  test "pending = no time at all and never attempted", ctx do
    pending = MapSet.new(RecipeTimeEstimation.pending_ids())
    assert MapSet.member?(pending, ctx.untimed.id)
    assert MapSet.member?(pending, ctx.untimed2.id)
    refute MapSet.member?(pending, ctx.timed.id)
    refute MapSet.member?(pending, ctx.prep_only.id)
  end

  test "apply_estimate fills only empty fields and stamps the recipe", ctx do
    RecipeTimeEstimation.apply_estimate(ctx.prep_only.id, %{prep: 30, cook: 12})
    RecipeTimeEstimation.apply_estimate(ctx.untimed.id, %{prep: 5, cook: 5})

    prep_only = Repo.get!(Recipe, ctx.prep_only.id)
    assert prep_only.preperation_time_lower_limit == 5
    assert prep_only.cooking_time_lower_limit == 12

    untimed = Repo.get!(Recipe, ctx.untimed.id)
    assert Food.total_time_minutes(untimed) == 10
    assert untimed.times_estimated_at
  end

  test "a run estimates every pending recipe and terminates on skipped ones", ctx do
    test_pid = self()

    stub(fn inputs ->
      send(test_pid, {:inputs, inputs})
      # The model times the omelette and skips the stew.
      {:ok, %{ctx.untimed.id => %{prep: 5, cook: 5}}}
    end)

    assert {:ok, run} = Food.enqueue_recipe_time_estimation()
    assert run.total >= 2
    assert {:error, :already_running} = Food.enqueue_recipe_time_estimation()

    Oban.drain_queue(queue: :ai_agents, with_recursion: true)

    assert_received {:inputs, inputs}
    assert Enum.any?(inputs, &(&1.title == "Untimed omelette" and is_list(&1.ingredients)))

    assert Food.total_time_minutes(Repo.get!(Recipe, ctx.untimed.id)) == 10
    stew = Repo.get!(Recipe, ctx.untimed2.id)
    assert Food.total_time_minutes(stew) == nil
    assert stew.times_estimated_at

    assert RecipeTimeEstimation.pending_ids() == []
    assert %{status: "completed"} = RecipeTimeEstimation.latest_run()
    assert %{missing: 0, attempted_without: n} = Food.recipe_time_coverage()
    assert n >= 1
    assert {:error, :nothing_pending} = Food.enqueue_recipe_time_estimation()
  end

  test "an estimator error fails the run", _ctx do
    stub(fn _ -> {:error, :boom} end)
    {:ok, run} = Food.enqueue_recipe_time_estimation()

    assert {:error, :boom} = perform_job(RecipeTimeEstimationWorker, %{"run_id" => run.id})
    assert %{status: "failed"} = RecipeTimeEstimation.get_run(run.id)
  end
end
