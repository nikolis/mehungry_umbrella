defmodule Mehungry.MealPlanJobsTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.AccountsFixtures
  alias Mehungry.{MealBlueprints, MealPlanJobs, Repo, Subscriptions}

  @worker "MehungryWeb.Api.MealPlanWorker"

  # A tracking row with a live Oban job behind it, as `create_and_enqueue/2` leaves it.
  defp live_job(status, attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()

    {:ok, job} =
      MealPlanJobs.create_and_enqueue(
        Map.merge(%{user_id: user.id, status: status}, attrs),
        &Oban.Job.new(%{"job_id" => &1.id}, worker: @worker, queue: :ai_interactive)
      )

    job
  end

  # What cancelling/discarding in Oban Web, or a timeout kill, leaves behind.
  defp kill_oban_job(job) do
    import Ecto.Query

    from(o in Oban.Job, where: fragment("?->>'job_id' = ?", o.args, ^to_string(job.id)))
    |> Repo.update_all(set: [state: "cancelled"])
  end

  defp later(job, seconds), do: NaiveDateTime.add(job.updated_at, seconds)

  describe "fail_if_stale/2" do
    test "leaves a live, recently-updated run alone" do
      for status <- ~w(queued generating) do
        job = live_job(status)
        assert %{status: ^status} = MealPlanJobs.fail_if_stale(job, later(job, 120))
      end
    end

    test "fails a job stuck generating past the limit, durably" do
      job = live_job("generating")

      assert %{status: "error", error: "generation timed out"} =
               MealPlanJobs.fail_if_stale(job, later(job, 601))

      assert %{status: "error"} = MealPlanJobs.get_job(job.id)
    end

    test "a queued run stays queued however long it waits, while its job is alive" do
      job = live_job("queued")
      assert %{status: "queued"} = MealPlanJobs.fail_if_stale(job, later(job, 86_400))
    end

    test "fails a queued or generating run whose Oban job is gone" do
      for status <- ~w(queued generating) do
        job = live_job(status)
        kill_oban_job(job)

        assert %{status: "error", error: "Meal plan generation was interrupted" <> _} =
                 MealPlanJobs.fail_if_stale(job)

        assert %{status: "error"} = MealPlanJobs.get_job(job.id)
      end
    end

    test "never touches finished jobs" do
      for status <- ~w(done error) do
        {:ok, job} =
          MealPlanJobs.create_job(%{user_id: AccountsFixtures.user_fixture().id, status: status})

        assert %{status: ^status} = MealPlanJobs.fail_if_stale(job, later(job, 86_400))
      end
    end

    test "does not overwrite a run that finished while we were deciding" do
      job = live_job("generating")
      kill_oban_job(job)
      {:ok, _} = MealPlanJobs.update_job(job, %{status: "done", result: %{"created_count" => 3}})

      # `job` is the stale struct we read earlier.
      assert %{status: "done"} = MealPlanJobs.fail_if_stale(job)
    end
  end

  describe "active_calendar_job/1" do
    test "a queued run whose job was cancelled no longer blocks the calendar" do
      job = live_job("queued")
      assert %{id: id} = MealPlanJobs.active_calendar_job(job.user_id)
      assert id == job.id

      kill_oban_job(job)

      assert MealPlanJobs.active_calendar_job(job.user_id) == nil
      assert %{status: "error"} = MealPlanJobs.get_job(job.id)
    end
  end

  describe "fail_stale_for_user/1 — blueprint plans" do
    defp generating_plan(user, age_seconds) do
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

      import Ecto.Query

      at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-age_seconds)
        |> NaiveDateTime.truncate(:second)

      Repo.update_all(from(p in plan.__struct__, where: p.id == ^plan.id), set: [inserted_at: at])
      plan
    end

    test "a generating plan with no run behind it is failed (an orphan can't block Generate)" do
      user = AccountsFixtures.user_fixture()
      plan = generating_plan(user, 3600)

      MealPlanJobs.fail_stale_for_user(user.id)

      assert %{status: "failed"} = MealBlueprints.get_plan!(user.id, plan.id)
    end

    test "a plan whose run is alive, or that was only just created, is left alone" do
      user = AccountsFixtures.user_fixture()
      with_run = generating_plan(user, 3600)
      fresh = generating_plan(user, 5)

      {:ok, _job} =
        MealPlanJobs.create_and_enqueue(
          %{user_id: user.id, status: "queued", blueprint_plan_id: with_run.id},
          &Oban.Job.new(%{"job_id" => &1.id}, worker: @worker, queue: :ai_interactive)
        )

      MealPlanJobs.fail_stale_for_user(user.id)

      assert %{status: "generating"} = MealBlueprints.get_plan!(user.id, with_run.id)
      assert %{status: "generating"} = MealBlueprints.get_plan!(user.id, fresh.id)
    end

    test "a plan whose run died is failed with it" do
      user = AccountsFixtures.user_fixture()
      plan = generating_plan(user, 5)

      {:ok, job} =
        MealPlanJobs.create_and_enqueue(
          %{user_id: user.id, status: "queued", blueprint_plan_id: plan.id},
          &Oban.Job.new(%{"job_id" => &1.id}, worker: @worker, queue: :ai_interactive)
        )

      kill_oban_job(job)
      MealPlanJobs.fail_stale_for_user(user.id)

      assert %{status: "failed"} = MealBlueprints.get_plan!(user.id, plan.id)
    end
  end

  describe "check_quota/1 — runs in flight count against the limit" do
    test "queued runs cannot overshoot the monthly allowance" do
      # m3hungry_plus: 4 own plans a month.
      job = live_job("queued")
      user_id = job.user_id
      {:ok, _} = Subscriptions.upsert_subscription(user_id, %{tier: "m3hungry_plus"})
      for _ <- 1..2, do: Subscriptions.record_usage(user_id, "meal_plan")

      # 2 used + 1 in flight = 3 of 4.
      assert MealPlanJobs.check_quota(user_id) == :ok

      {:ok, second} =
        MealPlanJobs.create_and_enqueue(
          %{user_id: user_id, status: "queued"},
          &Oban.Job.new(%{"job_id" => &1.id}, worker: @worker, queue: :ai_interactive)
        )

      # 2 used + 2 in flight = 4 of 4.
      assert MealPlanJobs.check_quota(user_id) == {:error, :quota_exceeded}

      # A dead run stops counting.
      kill_oban_job(second)
      assert MealPlanJobs.check_quota(user_id) == :ok
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
