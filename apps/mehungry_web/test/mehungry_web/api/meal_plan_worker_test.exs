defmodule MehungryWeb.Api.MealPlanWorkerTest do
  # async: false — the AI client stub is set through global application env.
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  alias Mehungry.AccountsFixtures
  alias Mehungry.MealPlanJobs
  alias MehungryWeb.Api.MealPlanWorker

  defmodule RaisingClient do
    def request(_params), do: raise("anthropic exploded")
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

    assert %{status: "error", error: "anthropic exploded"} = MealPlanJobs.get_job(job.id)
    assert_receive %Phoenix.Socket.Broadcast{event: "progress", payload: %{status: "error"}}
  end

  test "a job whose tracking row is gone is a no-op" do
    assert :ok = perform_job(MealPlanWorker, %{"job_id" => -1})
  end
end
