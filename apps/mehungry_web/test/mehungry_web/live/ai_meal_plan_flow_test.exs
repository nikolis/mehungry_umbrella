defmodule MehungryWeb.AiMealPlanFlowTest do
  @moduledoc """
  The AI meal-plan triggers end to end at the LiveView boundary:

    * generation is an **Oban job** on every surface (never a task tied to the
      page), and a page that re-mounts mid-run resumes its "running" state;
    * a week that already has meals makes the page **ask** fill-gaps vs replace
      before anything is enqueued;
    * the nutritionist surfaces run `NutritionistMealPlanAgent` under the
      `"nutritionist_meal_plan"` quota; the consumer surfaces run
      `UserMealPlanAgent` under `"meal_plan"`.

  The workers themselves are covered in their own tests — nothing is performed here.
  """
  use MehungryWeb.ConnCase
  use Oban.Testing, repo: Mehungry.Repo

  import Phoenix.LiveViewTest

  alias Mehungry.{History, MealBlueprints, MealPlanJobs, Repo, Subscriptions}
  alias Mehungry.ObanWorkers.NutritionistAgentWorker
  alias Mehungry.Professionals.TutorClientAssignment
  alias MehungryWeb.Api.MealPlanWorker

  defp viewport(conn),
    do: Phoenix.LiveViewTest.put_connect_params(conn, %{"viewport" => %{"width" => 1280}})

  defp log_meal(user_id, %Date{} = date, meal_type) do
    {:ok, start_dt} = NaiveDateTime.new(date, ~T[09:00:00])

    {:ok, meal} =
      History.create_user_meal(%{
        user_id: user_id,
        meal_type: meal_type,
        title: History.MealType.label(meal_type),
        start_dt: start_dt,
        end_dt: NaiveDateTime.add(start_dt, 3600)
      })

    meal
  end

  describe "consumer calendar (UserMealPlanAgent)" do
    setup %{conn: conn} do
      user = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _} = Subscriptions.upsert_subscription(user.id, %{tier: "m3hungry_plus"})
      %{conn: conn |> log_in_user(user) |> viewport(), user: user}
    end

    test "an empty week enqueues the job straight away — no prompt", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/calendar")

      html = render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})

      refute html =~ "meal-plan-mode-prompt"
      assert html =~ ~s(id="ai-plan-loading")

      monday = Date.beginning_of_week(Date.utc_today())
      job = MealPlanJobs.active_calendar_job(user.id)
      assert %{notes: "high protein", mode: "fill_gaps", start_date: ^monday} = job
      assert_enqueued(worker: MealPlanWorker, queue: :ai_interactive, args: %{"job_id" => job.id})
    end

    test "a week with meals asks first, and enqueues nothing until answered", %{
      conn: conn,
      user: user
    } do
      log_meal(user.id, Date.utc_today(), "lunch")
      {:ok, view, _html} = live(conn, ~p"/calendar")

      html = render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})

      assert html =~ "meal-plan-mode-prompt"
      assert html =~ "This week already has 1 meal."
      refute_enqueued(worker: MealPlanWorker)

      html = render_click(view, "ai_plan_mode", %{"mode" => "replace_week"})

      refute html =~ "meal-plan-mode-prompt"
      assert %{mode: "replace_week"} = MealPlanJobs.active_calendar_job(user.id)
      assert_enqueued(worker: MealPlanWorker)
    end

    test "cancelling the prompt enqueues nothing", %{conn: conn, user: user} do
      log_meal(user.id, Date.utc_today(), "lunch")
      {:ok, view, _html} = live(conn, ~p"/calendar")

      render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})
      html = render_click(view, "ai_plan_cancel", %{})

      refute html =~ "meal-plan-mode-prompt"
      refute_enqueued(worker: MealPlanWorker)
    end

    test "leaving and returning mid-run resumes the generating state", %{conn: conn, user: user} do
      {:ok, _job} = MealPlanWorker.enqueue(%{user_id: user.id, notes: "x"})

      {:ok, view, _html} = live(conn, ~p"/calendar")

      assert render(view) =~ ~s(id="ai-plan-loading")
    end

    test "the worker's result broadcast finishes the run on the page", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/calendar")
      render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})
      job = MealPlanJobs.active_calendar_job(user.id)

      MehungryWeb.Endpoint.broadcast(MealPlanWorker.topic(user.id), "result", %{
        job_id: job.id,
        blueprint_plan_id: nil,
        status: "done",
        meals: %{"created_count" => 35, "skipped_count" => 0, "meal_ids" => []}
      })

      html = render(view)
      assert html =~ "Added 35 meals to your calendar."
      refute html =~ ~s(id="ai-plan-loading")
    end

    test "a failure broadcast shows the readable error", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/calendar")
      render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})
      job = MealPlanJobs.active_calendar_job(user.id)

      MehungryWeb.Endpoint.broadcast(MealPlanWorker.topic(user.id), "progress", %{
        job_id: job.id,
        blueprint_plan_id: nil,
        status: "error",
        error: "Meal plan generation failed. Please try again."
      })

      html = render(view)
      assert html =~ "Meal plan generation failed. Please try again."
      refute html =~ ~s(id="ai-plan-loading")
    end

    test "a run whose worker died is noticed by the page without a reload", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/calendar")
      render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})
      assert render(view) =~ ~s(id="ai-plan-loading")

      # A timeout kill / cancel: no broadcast is ever sent.
      Repo.update_all(Oban.Job, set: [state: "discarded"])
      send(view.pid, :ai_plan_liveness)

      html = render(view)
      assert html =~ "Meal plan generation was interrupted"
      refute html =~ ~s(id="ai-plan-loading")
      assert MealPlanJobs.active_calendar_job(user.id) == nil
    end

    test "a cancelled queued run does not lock the button on the next visit", %{
      conn: conn,
      user: user
    } do
      {:ok, _job} = MealPlanWorker.enqueue(%{user_id: user.id, notes: "x"})
      Repo.update_all(Oban.Job, set: [state: "cancelled"])

      {:ok, view, _html} = live(conn, ~p"/calendar")

      refute render(view) =~ ~s(id="ai-plan-loading")
    end

    test "out of quota: nothing is enqueued", %{conn: conn, user: user} do
      {:ok, _} = Subscriptions.upsert_subscription(user.id, %{tier: "free"})
      {:ok, view, _html} = live(conn, ~p"/calendar")

      html = render_submit(view, "ai_plan_week", %{"prompt" => "high protein"})

      assert html =~ "reached your AI meal plan limit"
      refute_enqueued(worker: MealPlanWorker)
    end
  end

  describe "nutritionist surfaces (NutritionistMealPlanAgent)" do
    setup %{conn: conn} do
      nutritionist = Mehungry.AccountsFixtures.user_fixture()
      client = Mehungry.AccountsFixtures.user_fixture()

      {:ok, _} =
        Subscriptions.upsert_subscription(nutritionist.id, %{tier: "pro", status: "active"})

      Repo.insert!(%TutorClientAssignment{professional_id: nutritionist.id, client_id: client.id})

      %{
        conn: conn |> log_in_user(nutritionist) |> viewport(),
        nutritionist: nutritionist,
        client: client
      }
    end

    test "client calendar: an empty week enqueues the nutritionist draft", %{
      conn: conn,
      nutritionist: nutritionist,
      client: client
    } do
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}/calendar")

      html = render_submit(view, "ai_plan_week", %{"prompt" => "Mediterranean"})

      assert html =~ "Planning…"

      assert_enqueued(
        worker: NutritionistAgentWorker,
        args: %{
          "professional_id" => nutritionist.id,
          "client_id" => client.id,
          "preferences" => "Mediterranean",
          "mode" => "fill_gaps",
          "start_date" => Date.to_iso8601(Date.beginning_of_week(Date.utc_today()))
        }
      )

      # The consumer worker is never used on the nutritionist side.
      refute_enqueued(worker: MealPlanWorker)
    end

    test "client calendar: a week with meals asks fill-gaps vs replace first", %{
      conn: conn,
      client: client
    } do
      log_meal(client.id, Date.utc_today(), "lunch")
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}/calendar")

      html = render_submit(view, "ai_plan_week", %{"prompt" => ""})

      assert html =~ "meal-plan-mode-prompt"
      assert html =~ "on the client&#39;s calendar"
      refute_enqueued(worker: NutritionistAgentWorker)

      render_click(view, "ai_plan_mode", %{"mode" => "replace_week"})

      assert_enqueued(worker: NutritionistAgentWorker, args: %{"mode" => "replace_week"})
    end

    test "client calendar: only this client's events are acted on", %{
      conn: conn,
      nutritionist: nutritionist,
      client: client
    } do
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}/calendar")
      topic = NutritionistAgentWorker.topic(nutritionist.id)

      Phoenix.PubSub.broadcast(
        Mehungry.PubSub,
        topic,
        {:nutritionist_agent, -1, {:done, "OTHER CLIENT"}}
      )

      refute render(view) =~ "OTHER CLIENT"

      Phoenix.PubSub.broadcast(
        Mehungry.PubSub,
        topic,
        {:nutritionist_agent, client.id, {:done, "✓ 12 meal entries created."}}
      )

      assert render(view) =~ "12 meal entries created"
    end

    test "client calendar: a draft that died silently stops spinning", %{
      conn: conn,
      client: client
    } do
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}/calendar")
      render_submit(view, "ai_plan_week", %{"prompt" => "Mediterranean"})
      assert render(view) =~ "Planning…"

      # While the job is alive the confirm step does nothing.
      send(view.pid, :ai_liveness_confirm)
      assert render(view) =~ "Planning…"

      Repo.update_all(Oban.Job, set: [state: "discarded"])
      send(view.pid, :ai_liveness_confirm)

      html = render(view)
      refute html =~ "Planning…"
      assert html =~ "Meal plan generation failed. Please try again."
    end

    test "client file: a draft that died silently stops spinning", %{conn: conn, client: client} do
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}?tab=planning")
      render_submit(view, "ai_assist", %{"preferences" => "", "week" => "this"})

      Repo.update_all(Oban.Job, set: [state: "discarded"])
      send(view.pid, :ai_liveness_confirm)

      assert render(view) =~ "Meal plan generation failed. Please try again."
    end

    test "client file: AI Assist asks first when the chosen week has meals", %{
      conn: conn,
      client: client
    } do
      log_meal(client.id, Date.utc_today(), "dinner")
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}?tab=planning")

      html = render_submit(view, "ai_assist", %{"preferences" => "low-carb", "week" => "this"})

      assert html =~ "meal-plan-mode-prompt"
      refute_enqueued(worker: NutritionistAgentWorker)

      render_click(view, "ai_assist_mode", %{"mode" => "fill_gaps"})

      assert_enqueued(
        worker: NutritionistAgentWorker,
        args: %{"preferences" => "low-carb", "mode" => "fill_gaps"}
      )
    end

    test "client file: 'next week' plans the following Monday, with no prompt for an empty week",
         %{conn: conn, client: client} do
      log_meal(client.id, Date.utc_today(), "dinner")
      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}?tab=planning")

      html = render_submit(view, "ai_assist", %{"preferences" => "", "week" => "next"})

      refute html =~ "meal-plan-mode-prompt"
      next_monday = Date.add(Date.beginning_of_week(Date.utc_today()), 7)

      assert_enqueued(
        worker: NutritionistAgentWorker,
        args: %{"start_date" => Date.to_iso8601(next_monday)}
      )
    end

    test "client file: the client-plan quota is enforced", %{
      conn: conn,
      nutritionist: nutritionist,
      client: client
    } do
      for _ <- 1..40, do: Subscriptions.record_usage(nutritionist.id, "nutritionist_meal_plan")

      {:ok, view, _html} = live(conn, "/nutritionist/clients/#{client.id}?tab=planning")
      html = render_submit(view, "ai_assist", %{"preferences" => "", "week" => "this"})

      assert html =~ "reached your AI client-plan limit"
      refute_enqueued(worker: NutritionistAgentWorker)
    end
  end

  describe "blueprint plans" do
    setup %{conn: conn} do
      user = Mehungry.AccountsFixtures.user_fixture()
      {:ok, _} = Subscriptions.upsert_subscription(user.id, %{tier: "pro", status: "active"})

      {:ok, blueprint} =
        MealBlueprints.create_blueprint(
          MealBlueprints.default_blueprint_attrs(user.id, "Flow BP")
        )

      %{conn: log_in_user(conn, user), user: user, blueprint: blueprint}
    end

    test "Generate hands the run to the shared worker, tied to the new plan row", %{
      conn: conn,
      user: user,
      blueprint: blueprint
    } do
      {:ok, view, _html} = live(conn, "/nutritionist/blueprints")

      html = render_click(view, "generate", %{"id" => to_string(blueprint.id)})
      assert html =~ "Generating…"

      [plan] = MealBlueprints.list_plans_for_blueprint(user.id, blueprint.id)
      assert plan.status == "generating"

      [job] = Repo.all(Mehungry.MealPlanJobs.MealPlanJob)
      assert job.blueprint_plan_id == plan.id
      assert job.blueprint_id == blueprint.id
      assert_enqueued(worker: MealPlanWorker, args: %{"job_id" => job.id})

      # A blueprint-plan run never shows up as the user's calendar run.
      assert MealPlanJobs.active_calendar_job(user.id) == nil
    end

    test "runs still in flight count against the quota (no overshoot across blueprints)", %{
      conn: conn,
      user: user,
      blueprint: blueprint
    } do
      {:ok, second} =
        MealBlueprints.create_blueprint(
          MealBlueprints.default_blueprint_attrs(user.id, "Other BP")
        )

      # Pro allows 10 own plans a month: 9 used, so one more may run.
      for _ <- 1..9, do: Subscriptions.record_usage(user.id, "meal_plan")
      {:ok, view, _html} = live(conn, "/nutritionist/blueprints")

      render_click(view, "generate", %{"id" => to_string(blueprint.id)})
      html = render_click(view, "generate", %{"id" => to_string(second.id)})

      assert html =~ "reached your meal-plan generation limit"
      assert [_only_one] = all_enqueued(worker: MealPlanWorker)
    end

    test "a run that died silently re-enables Generate", %{conn: conn, blueprint: blueprint} do
      {:ok, view, _html} = live(conn, "/nutritionist/blueprints")
      render_click(view, "generate", %{"id" => to_string(blueprint.id)})
      assert render(view) =~ "Generating…"

      Repo.update_all(Oban.Job, set: [state: "discarded"])
      send(view.pid, :generation_liveness)

      refute render(view) =~ "Generating…"
    end

    test "re-opening the page mid-run still shows the blueprint as generating", %{
      conn: conn,
      blueprint: blueprint
    } do
      {:ok, view, _html} = live(conn, "/nutritionist/blueprints")
      render_click(view, "generate", %{"id" => to_string(blueprint.id)})

      {:ok, _view2, html} = live(conn, "/nutritionist/blueprints")
      assert html =~ "Generating…"
    end
  end
end
