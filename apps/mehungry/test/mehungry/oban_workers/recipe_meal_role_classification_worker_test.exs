defmodule Mehungry.ObanWorkers.RecipeMealRoleClassificationWorkerTest do
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.Food.{MealRoleAssignments, Recipe, RecipeMealRoleRuns}
  alias Mehungry.ObanWorkers.RecipeMealRoleClassificationWorker, as: Worker
  alias Mehungry.Repo

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :meal_role_classifier_stub) end)
    user = user_fixture()
    # Only our recipes are unclassified, so a run's batches are deterministic.
    Repo.update_all(Recipe, set: [meal_roles_classified_at: DateTime.utc_now(:second)])
    %{user: user}
  end

  defp stub(fun), do: Application.put_env(:mehungry, :meal_role_classifier_stub, fun)

  defp unstamp(ids) do
    Repo.update_all(from(r in Recipe, where: r.id in ^ids), set: [meal_roles_classified_at: nil])
  end

  test "single-recipe job classifies with ingredients + nutrition and broadcasts", %{user: user} do
    recipe = recipe_fixture(user, %{title: "Moussaka"})
    test_pid = self()
    Phoenix.PubSub.subscribe(Mehungry.PubSub, RecipeMealRoleRuns.topic())

    stub(fn [input] ->
      send(test_pid, {:input, input})
      {:ok, %{input.id => [%{role: "main", confidence: 0.97}]}}
    end)

    assert :ok = perform_job(Worker, %{"recipe_id" => recipe.id})

    assert_received {:input, %{id: id, title: "Moussaka", ingredients: [_ | _]}}
    assert id == recipe.id
    assert MealRoleAssignments.roles_for([recipe.id]) == %{recipe.id => ["main"]}
    assert_received {:recipe_meal_roles_updated, ^id}
  end

  test "a classifier error fails the job (Oban retries)", %{user: user} do
    recipe = recipe_fixture(user, %{})
    stub(fn _ -> {:error, :timeout} end)
    assert {:error, :timeout} = perform_job(Worker, %{"recipe_id" => recipe.id})
  end

  test "a run walks every pending recipe in batches and completes", %{user: user} do
    recipes = for _ <- 1..3, do: recipe_fixture(user, %{})
    ids = Enum.map(recipes, & &1.id)
    unstamp(ids)

    # The model skips the last recipe — it must still be stamped, so the run
    # cannot loop on it.
    stub(fn inputs ->
      {:ok, inputs |> Enum.drop(-1) |> Map.new(&{&1.id, [%{role: "side", confidence: 0.5}]})}
    end)

    {:ok, run} = MealRoleAssignments.enqueue_classification("unclassified")
    assert run.total == 3

    assert :ok =
             perform_job(Worker, %{
               "run_id" => run.id,
               "mode" => "unclassified",
               "since" => DateTime.to_iso8601(run.started_at)
             })

    # Batch 1 classified everything and enqueued the follow-up batch…
    assert RecipeMealRoleRuns.get_run(run.id).processed == 3
    assert_enqueued(worker: Worker, args: %{"run_id" => run.id})
    assert MealRoleAssignments.pending_classification_ids("unclassified") == []

    # …which finds nothing pending and completes the run.
    assert :ok = perform_job(Worker, %{"run_id" => run.id, "mode" => "unclassified"})
    assert RecipeMealRoleRuns.get_run(run.id).status == "completed"
    assert map_size(MealRoleAssignments.roles_for(ids)) == 2
  end

  test "a failed batch marks the run failed", %{user: user} do
    recipe = recipe_fixture(user, %{})
    unstamp([recipe.id])
    stub(fn _ -> {:error, :overloaded} end)

    {:ok, run} = MealRoleAssignments.enqueue_classification("unclassified")

    assert {:error, :overloaded} =
             perform_job(Worker, %{"run_id" => run.id, "mode" => "unclassified"})

    assert RecipeMealRoleRuns.get_run(run.id).status == "failed"
  end
end
