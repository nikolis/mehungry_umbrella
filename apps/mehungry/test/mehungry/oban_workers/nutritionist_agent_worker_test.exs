defmodule Mehungry.ObanWorkers.NutritionistAgentWorkerTest do
  @moduledoc """
  The single front door + runner behind both nutritionist AI surfaces: quota
  (`"nutritionist_meal_plan"`, Pro only), one draft per client at a time, the
  existing-meals modes, and the rule that a client's past days are never touched.
  The model is scripted — no network.
  """
  # async: false — the AI client stub is set through global application env.
  use Mehungry.DataCase, async: false
  use Oban.Testing, repo: Mehungry.Repo

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.{History, Repo, Subscriptions}
  alias Mehungry.AI.{EmbeddingClientStub, ScriptedClient}
  alias Mehungry.Food.Recipe
  alias Mehungry.ObanWorkers.NutritionistAgentWorker

  @feature "nutritionist_meal_plan"

  setup do
    professional = user_fixture()
    client = user_fixture()
    {:ok, _} = Subscriptions.upsert_subscription(professional.id, %{tier: "pro"})
    on_exit(&ScriptedClient.reset/0)

    %{professional: professional, client: client, today: Date.utc_today()}
  end

  describe "quota" do
    test "Pro gets 40 client plans a month; other tiers none" do
      assert Subscriptions.monthly_limit("pro", @feature) == 40
      assert Subscriptions.monthly_limit("m3hungry_plus", @feature) == 0
      assert Subscriptions.monthly_limit("free", @feature) == 0
      # …and it is a separate allowance from the nutritionist's own plans.
      assert Subscriptions.monthly_limit("pro", "meal_plan") == 10
    end

    test "start/1 refuses a nutritionist without quota and enqueues nothing", ctx do
      free = user_fixture()

      assert {:error, :quota_exceeded} =
               NutritionistAgentWorker.start(%{
                 professional_id: free.id,
                 client_id: ctx.client.id
               })

      refute_enqueued(worker: NutritionistAgentWorker)
    end

    test "drafts still queued count against the allowance (no overshoot across clients)", ctx do
      for _ <- 1..39, do: Subscriptions.record_usage(ctx.professional.id, @feature)

      # 39 used + this one in flight = 40 of 40.
      assert {:ok, _job} = start(ctx)
      assert NutritionistAgentWorker.in_flight_count(ctx.professional.id) == 1

      other_client = user_fixture()

      assert {:error, :quota_exceeded} =
               NutritionistAgentWorker.start(%{
                 professional_id: ctx.professional.id,
                 client_id: other_client.id
               })
    end

    test "start/1 refuses once the month's allowance is used", ctx do
      for _ <- 1..40, do: Subscriptions.record_usage(ctx.professional.id, @feature)

      assert {:error, :quota_exceeded} = start(ctx)
    end
  end

  describe "start/1" do
    test "enqueues the draft with its week and mode", ctx do
      monday = Date.beginning_of_week(ctx.today)

      assert {:ok, _job} = start(ctx, %{start_date: monday, mode: :replace_week})

      assert_enqueued(
        worker: NutritionistAgentWorker,
        args: %{
          "professional_id" => ctx.professional.id,
          "client_id" => ctx.client.id,
          "start_date" => Date.to_iso8601(monday),
          "mode" => "replace_week"
        }
      )

      assert NutritionistAgentWorker.running?(ctx.professional.id, ctx.client.id)
    end

    test "a second draft for the same client while one is in flight is refused", ctx do
      assert {:ok, _job} = start(ctx)
      assert {:error, :already_running} = start(ctx)

      # A different client is independent.
      other_client = user_fixture()

      assert {:ok, _job} =
               NutritionistAgentWorker.start(%{
                 professional_id: ctx.professional.id,
                 client_id: other_client.id
               })
    end

    test "a week that is entirely in the past is refused", ctx do
      assert {:error, :week_in_past} = start(ctx, %{start_date: Date.add(ctx.today, -14)})
    end
  end

  describe "perform/1" do
    test "writes the draft to the client's calendar, meters the nutritionist, reports done",
         ctx do
      recipe = searchable_recipe(ctx.professional, "worker lentil bowl")
      script_plan(recipe, [{ctx.today, "Lunch"}, {ctx.today, "Dinner"}])
      subscribe(ctx)

      assert :ok = perform(ctx, %{"start_date" => Date.to_iso8601(ctx.today)})

      meals = week_meals(ctx.client.id, ctx.today)
      assert Enum.map(meals, & &1.meal_type) |> Enum.sort() == ["dinner", "lunch"]

      assert Subscriptions.get_usage_this_month(ctx.professional.id, @feature) == 1
      # The client is never charged, and the nutritionist's own-plan quota is untouched.
      assert Subscriptions.get_usage_this_month(ctx.client.id, @feature) == 0
      assert Subscriptions.get_usage_this_month(ctx.professional.id, "meal_plan") == 0

      client_id = ctx.client.id
      assert_receive {:nutritionist_agent, ^client_id, {:started, _}}
      assert_receive {:nutritionist_agent, ^client_id, {:step, "Searching recipe catalog…"}}
      assert_receive {:nutritionist_agent, ^client_id, {:done, summary}}
      assert summary =~ "2 meal entries created"
    end

    test "fill-gaps keeps a meal already on the calendar even if the model plans that cell",
         ctx do
      recipe = searchable_recipe(ctx.professional, "worker gap bowl")
      existing = log_meal(ctx.client.id, ctx.today, "lunch")
      # The model ignores the instruction and plans the taken Lunch cell anyway.
      script_plan(recipe, [{ctx.today, "Lunch"}, {ctx.today, "Dinner"}])

      assert :ok =
               perform(ctx, %{"start_date" => Date.to_iso8601(ctx.today), "mode" => "fill_gaps"})

      meals = week_meals(ctx.client.id, ctx.today)
      assert existing.id in Enum.map(meals, & &1.id)
      assert Enum.count(meals, &(&1.meal_type == "lunch")) == 1
      assert Enum.count(meals, &(&1.meal_type == "dinner")) == 1
    end

    test "replace mode rebuilds from today on but never deletes the client's past days", ctx do
      week_start = Date.add(ctx.today, -2)
      recipe = searchable_recipe(ctx.professional, "worker replace bowl")
      eaten = log_meal(ctx.client.id, week_start, "lunch")
      planned = log_meal(ctx.client.id, ctx.today, "lunch")
      # A replacing plan must cover the main meals of every day still in play
      # (today + the 4 days left in this week).
      cells = for day <- 0..4, slot <- ["Breakfast", "Lunch", "Dinner"], do: {Date.add(ctx.today, day), slot}
      script_plan(recipe, cells)

      assert :ok =
               perform(ctx, %{
                 "start_date" => Date.to_iso8601(week_start),
                 "mode" => "replace_week"
               })

      ids = ctx.client.id |> week_meals(week_start) |> Enum.map(& &1.id)
      assert eaten.id in ids
      refute planned.id in ids
      assert length(ids) == 16
    end

    test "replace mode: a thin plan is refused and the client's week is left untouched", ctx do
      recipe = searchable_recipe(ctx.professional, "worker thin bowl")
      planned = log_meal(ctx.client.id, ctx.today, "lunch")
      # One meal for a whole week, and the model gives up after being sent back.
      script_plan(recipe, [{ctx.today, "Dinner"}])

      assert {:error, :no_plan_submitted} =
               perform(ctx, %{
                 "start_date" => Date.to_iso8601(ctx.today),
                 "mode" => "replace_week"
               })

      assert [%{id: id}] = week_meals(ctx.client.id, ctx.today)
      assert id == planned.id
      assert Subscriptions.get_usage_this_month(ctx.professional.id, @feature) == 0
    end

    test "tells the nutritionist which foods were excluded — on success and on failure", ctx do
      {:ok, record} =
        Mehungry.Professionals.create_client_record(%{
          professional_id: ctx.professional.id,
          user_id: ctx.client.id,
          full_name: "Client"
        })

      {:ok, _} =
        Mehungry.Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "details" => %{"allergies" => "no", "food_aversions" => "oil, ham"}
        })

      safe = searchable_recipe(ctx.professional, "boiled graham bowl")
      subscribe(ctx)
      client_id = ctx.client.id

      # "oil"/"ham" are enforced at word starts, so "boiled graham" survives; "no" is dropped.
      script_plan(safe, [{ctx.today, "Lunch"}])
      assert :ok = perform(ctx, %{"start_date" => Date.to_iso8601(ctx.today)})
      assert_receive {:nutritionist_agent, ^client_id, {:done, summary}}
      assert summary =~ "Foods excluded for this client: oil, ham."

      ScriptedClient.script([ScriptedClient.end_turn("Nothing fits.")])
      assert {:error, :no_plan_submitted} = perform(ctx, %{"start_date" => Date.to_iso8601(ctx.today)})
      assert_receive {:nutritionist_agent, ^client_id, {:error, message}}
      assert message =~ "Foods excluded for this client: oil, ham."
    end

    test "a failed run charges nothing and reports a readable error", ctx do
      ScriptedClient.script([{:error, "API returned status 500"}])
      subscribe(ctx)

      assert {:error, _} = perform(ctx, %{"start_date" => Date.to_iso8601(ctx.today)})

      assert week_meals(ctx.client.id, ctx.today) == []
      assert Subscriptions.get_usage_this_month(ctx.professional.id, @feature) == 0

      client_id = ctx.client.id
      assert_receive {:nutritionist_agent, ^client_id, {:error, message}}
      assert message == "Meal plan generation failed. Please try again."
    end

    test "a run that ends without a submitted plan is an error, not a silent 'done'", ctx do
      ScriptedClient.script([ScriptedClient.end_turn("Nothing suitable found.")])
      subscribe(ctx)

      assert {:error, :no_plan_submitted} =
               perform(ctx, %{"start_date" => Date.to_iso8601(ctx.today)})

      assert Subscriptions.get_usage_this_month(ctx.professional.id, @feature) == 0
      client_id = ctx.client.id
      assert_receive {:nutritionist_agent, ^client_id, {:error, _}}
      refute_received {:nutritionist_agent, ^client_id, {:done, _}}
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────────

  defp start(ctx, extra \\ %{}) do
    NutritionistAgentWorker.start(
      Map.merge(
        %{
          professional_id: ctx.professional.id,
          client_id: ctx.client.id,
          client_name: "Client",
          preferences: "low-carb"
        },
        extra
      )
    )
  end

  defp perform(ctx, extra) do
    perform_job(
      NutritionistAgentWorker,
      Map.merge(
        %{
          "professional_id" => ctx.professional.id,
          "client_id" => ctx.client.id,
          "client_name" => "Client",
          "preferences" => ""
        },
        extra
      )
    )
  end

  defp subscribe(ctx) do
    Phoenix.PubSub.subscribe(
      Mehungry.PubSub,
      NutritionistAgentWorker.topic(ctx.professional.id)
    )
  end

  # The model searches (so the recipe is "offered"), submits `cells`, then ends.
  defp script_plan(recipe, cells) do
    entries =
      Enum.map(cells, fn {date, slot} ->
        %{
          "date" => Date.to_string(date),
          "slot" => slot,
          "recipe_id" => recipe.id,
          "cooking_portions" => 2
        }
      end)

    ScriptedClient.script([
      ScriptedClient.tool_use("search_recipes", %{"query" => recipe.title}),
      ScriptedClient.tool_use("submit_plan", %{"entries" => entries, "rationale" => "A note."}),
      ScriptedClient.end_turn("Done.")
    ])
  end

  defp searchable_recipe(owner, title) do
    recipe = recipe_fixture(owner, %{title: title, servings: 2})

    Repo.update_all(
      from(r in Recipe, where: r.id == ^recipe.id),
      set: [embedding: Pgvector.new(EmbeddingClientStub.vector(title))]
    )

    recipe
  end

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

  defp week_meals(user_id, start_date),
    do: History.list_calendar_user_meals(user_id, start_date, Date.add(start_date, 6))
end
