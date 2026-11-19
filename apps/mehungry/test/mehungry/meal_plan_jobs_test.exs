defmodule Mehungry.MealPlanJobsTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.MealPlanJobs

  defp job(status) do
    user = AccountsFixtures.user_fixture()
    {:ok, job} = MealPlanJobs.create_job(%{user_id: user.id, status: status})
    job
  end

  defp later(job, seconds), do: NaiveDateTime.add(job.updated_at, seconds)

  describe "fail_if_stale/2" do
    test "leaves a recently-updated generating job alone" do
      job = job("generating")
      assert %{status: "generating"} = MealPlanJobs.fail_if_stale(job, later(job, 120))
    end

    test "fails a job stuck generating past the limit, durably" do
      job = job("generating")

      assert %{status: "error", error: "generation timed out"} =
               MealPlanJobs.fail_if_stale(job, later(job, 601))

      assert %{status: "error"} = MealPlanJobs.get_job(job.id)
    end

    test "never touches queued or finished jobs, however old" do
      for status <- ~w(queued done error) do
        job = job(status)
        assert %{status: ^status} = MealPlanJobs.fail_if_stale(job, later(job, 86_400))
      end
    end
  end

  describe "create_and_enqueue/2" do
    test "an invalid row enqueues nothing" do
      assert {:error, %Ecto.Changeset{}} =
               MealPlanJobs.create_and_enqueue(%{status: "queued"}, fn _ ->
                 flunk("must not build a job")
               end)
    end
  end
end
