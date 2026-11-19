defmodule MehungryWeb.Api.MealPlanWorkerTest do
  # async: false — the AI client stub is set through global application env.
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.AccountsFixtures
  alias Mehungry.MealBlueprints
  alias Mehungry.MealPlanJobs
  alias Mehungry.Subscriptions
  alias MehungryWeb.Api.MealPlanWorker

  defmodule RaisingClient do
    def request(_params), do: raise("anthropic exploded")
  end

  defmodule ErrorClient do
    def request(_params), do: {:error, "API returned status 500"}
  end

  setup do
    Application.put_env(:mehungry, :ai_client, RaisingClient)
    on_exit(fn -> Application.delete_env(:mehungry, :ai_client) end)
    :ok
  end

  test "runs on the dedicated interactive queue" do
    assert %Ecto.Changeset{changes: %{queue: "ai_interactive"}} =
             MealPlanWorker.new(%{"job_id" => 1})
  end

  test "a crash mid-generation lands the tracking row in error, never generating" do
    user = AccountsFixtures.user_fixture()

    {:ok, job} =
      MealPlanJobs.create_job(%{user_id: user.id, status: "queued", notes: "high protein"})

    MehungryWeb.Endpoint.subscribe("meal_plan:#{user.id}")

    assert {:error, _} = perform_job(MealPlanWorker, %{"job_id" => job.id})

    # The raw exception is logged, never stored on the row a client reads.
    assert %{status: "error", error: "Meal plan generation failed. Please try again."} =
             MealPlanJobs.get_job(job.id)

    assert_receive %Phoenix.Socket.Broadcast{event: "progress", payload: %{status: "error"}}
    assert Subscriptions.get_usage_this_month(user.id, "meal_plan") == 0
  end

  test "an agent error fails the run without any fallback plan or quota charge" do
    Application.put_env(:mehungry, :ai_client, ErrorClient)
    user = AccountsFixtures.user_fixture()
    {:ok, job} = MealPlanJobs.create_job(%{user_id: user.id, status: "queued", notes: "vegan"})

    assert :ok = perform_job(MealPlanWorker, %{"job_id" => job.id})

    assert %{status: "error"} = MealPlanJobs.get_job(job.id)
    assert Mehungry.History.list_history_user_meals_for_user(user.id) == []
    assert Subscriptions.get_usage_this_month(user.id, "meal_plan") == 0
  end

  test "a failed blueprint-plan run marks the plan failed instead of leaving it generating" do
    Application.put_env(:mehungry, :ai_client, ErrorClient)
    user = AccountsFixtures.user_fixture()

    {:ok, blueprint} =
      MealBlueprints.create_blueprint(MealBlueprints.default_blueprint_attrs(user.id, "BP"))

    {:ok, plan} =
      MealBlueprints.create_plan(%{
        name: "Plan",
        start_date: Date.utc_today(),
        status: "generating",
        blueprint_id: blueprint.id,
        user_id: user.id
      })

    {:ok, job} =
      MealPlanJobs.create_job(%{
        user_id: user.id,
        status: "queued",
        blueprint_id: blueprint.id,
        blueprint_plan_id: plan.id
      })

    MehungryWeb.Endpoint.subscribe("meal_plan:#{user.id}")
    assert :ok = perform_job(MealPlanWorker, %{"job_id" => job.id})

    assert %{status: "failed"} = MealBlueprints.get_plan!(user.id, plan.id)
    plan_id = plan.id

    assert_receive %Phoenix.Socket.Broadcast{
      event: "progress",
      payload: %{status: "error", blueprint_plan_id: ^plan_id}
    }
  end

  test "a requested blueprint that cannot be resolved fails the run (constraints are never dropped)" do
    user = AccountsFixtures.user_fixture()
    {:ok, job} = MealPlanJobs.create_job(%{user_id: user.id, status: "queued"})

    # No FK-valid blueprint the user may use: simulate with a foreign private one.
    other = AccountsFixtures.user_fixture()

    {:ok, foreign} =
      MealBlueprints.create_blueprint(MealBlueprints.default_blueprint_attrs(other.id, "Private"))

    {:ok, job} = MealPlanJobs.update_job(job, %{blueprint_id: foreign.id})

    assert :ok = perform_job(MealPlanWorker, %{"job_id" => job.id})

    assert %{status: "error", error: "That blueprint is no longer available."} =
             MealPlanJobs.get_job(job.id)
  end

  test "enqueue/1 creates the row and its job together" do
    user = AccountsFixtures.user_fixture()

    assert {:ok, job} = MealPlanWorker.enqueue(%{user_id: user.id, mode: "replace_week"})
    assert job.status == "queued"
    assert job.mode == "replace_week"
    assert_enqueued(worker: MealPlanWorker, args: %{"job_id" => job.id})
  end

  test "a job whose tracking row is gone is a no-op" do
    assert :ok = perform_job(MealPlanWorker, %{"job_id" => -1})
  end
end
