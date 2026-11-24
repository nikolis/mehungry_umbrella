defmodule Mehungry.AI.Agents.NutritionistMealPlanAgentTest do
  @moduledoc """
  Deterministic coverage of `NutritionistMealPlanAgent`'s tools and guards:

    * get_client_record — merges intake (goal/TDEE), linked conditions, and the
      client's profile (diet/avoid_foods) into one brief, incl. a unified `avoid`
      list and a calorie_target.
    * get_assigned_plan — the week's already-assigned meals (today onward), with a
      mode-aware instruction (fill gaps vs replace).
    * submit_plan — validates + returns entries; never persists, never accepts a
      past day or an id the search did not offer.
    * guards — the client's diet / avoid list / condition-implicated ingredients
      are filtered out of search results deterministically.
    * catalog — the nutritionist's own recipes, else the public catalog.
    * search_recipes — returns per-serving calories from the recipe's nutrients.

  No LLM — the tool handlers are driven directly through the `handle_tool/3` seam.
  """
  use Mehungry.DataCase, async: false

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.{Professionals, History, Repo}
  alias Mehungry.Health.Condition
  alias Mehungry.Food.Recipe
  alias Mehungry.AI.EmbeddingClientStub
  alias Mehungry.AI.Agents.NutritionistMealPlanAgent

  describe "get_client_record" do
    test "merges intake, conditions and profile into one brief with a unified avoid list" do
      professional = user_fixture()
      client = user_fixture()

      {:ok, record} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "Maria Papadaki"
        })

      {:ok, _intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "tdee_kcal" => 1800,
          "goal" => "weight_loss",
          "details" => %{"allergies" => "shellfish, peanuts"}
        })

      condition = Repo.insert!(%Condition{name: "Gout"})
      Professionals.add_client_condition(record.id, condition.id)

      # The client also set their own calorie target — the clinician's intake TDEE
      # must win over the client's self-entered profile value.
      put_profile(client.id, %{
        diet: "vegetarian",
        avoid_foods: ["shrimp"],
        daily_calorie_target: 2500
      })

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)
      {result, ^acc} = NutritionistMealPlanAgent.handle_tool("get_client_record", %{}, acc)

      assert result.has_record
      assert result.diet == "vegetarian"
      # nutritionist (intake TDEE) wins over the client's profile target (2500)
      assert result.calorie_target == 1800
      assert result.goal == "weight_loss"
      assert "Gout" in result.conditions

      # avoid merges profile.avoid_foods + intake allergy terms (split + trimmed)
      assert "shrimp" in result.avoid
      assert "shellfish" in result.avoid
      assert "peanuts" in result.avoid
    end

    test "falls back to the profile daily_calorie_target when there is no intake TDEE" do
      professional = user_fixture()
      client = user_fixture()

      {:ok, _record} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "No Intake"
        })

      put_profile(client.id, %{daily_calorie_target: 2200})

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)
      {result, _acc} = NutritionistMealPlanAgent.handle_tool("get_client_record", %{}, acc)

      assert result.calorie_target == 2200
    end

    test "is safe when the client has no record or profile" do
      professional = user_fixture()
      client = user_fixture()

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)
      {result, _acc} = NutritionistMealPlanAgent.handle_tool("get_client_record", %{}, acc)

      refute result.has_record
      assert result.diet == "omnivore"
      assert result.calorie_target == nil
      assert result.avoid == []
      assert result.conditions == []
    end
  end

  describe "get_assigned_plan" do
    test "fill-gaps mode lists the taken cells and tells the model to leave them" do
      professional = user_fixture()
      client = user_fixture()

      today = Date.utc_today()
      tomorrow = Date.add(today, 1)

      assign_meal(client.id, today, "breakfast", ~T[08:00:00])
      assign_meal(client.id, tomorrow, "lunch", ~T[13:00:00])

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id, start_date: today)
      {result, ^acc} = NutritionistMealPlanAgent.handle_tool("get_assigned_plan", %{}, acc)

      assert result.assigned_count == 2

      assert %{date: Date.to_string(today), slot: "Breakfast", items: []} in result.assigned_entries

      assert result.message =~ "do NOT plan them"
    end

    test "replace mode tells the model the listed meals will be replaced" do
      professional = user_fixture()
      client = user_fixture()
      today = Date.utc_today()
      assign_meal(client.id, today, "breakfast", ~T[08:00:00])

      acc =
        NutritionistMealPlanAgent.new_acc(professional.id, client.id,
          start_date: today,
          mode: :replace_week
        )

      {result, _acc} = NutritionistMealPlanAgent.handle_tool("get_assigned_plan", %{}, acc)

      assert result.assigned_count == 1
      assert result.message =~ "REPLACED"
    end

    test "only the part of the week from today onward is in play" do
      professional = user_fixture()
      client = user_fixture()
      today = Date.utc_today()
      week_start = Date.add(today, -3)

      assign_meal(client.id, Date.add(today, -2), "breakfast", ~T[08:00:00])

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id, start_date: week_start)

      assert acc.first_day == today
      {result, _acc} = NutritionistMealPlanAgent.handle_tool("get_assigned_plan", %{}, acc)
      assert result.assigned_count == 0
    end
  end

  describe "submit_plan" do
    test "validates and hands the entries back — the agent itself persists nothing" do
      professional = user_fixture()
      client = user_fixture()
      recipe = recipe_fixture(professional, %{title: "test recipe", servings: 2})
      today = Date.utc_today()

      acc =
        professional.id
        |> NutritionistMealPlanAgent.new_acc(client.id, start_date: today)
        |> Map.put(:offered, MapSet.new([recipe.id]))

      entries = [
        %{
          "date" => Date.to_string(today),
          "slot" => "Breakfast",
          "recipe_id" => recipe.id,
          "cooking_portions" => 2
        }
      ]

      {result, new_acc} =
        NutritionistMealPlanAgent.handle_tool(
          "submit_plan",
          %{"entries" => entries, "rationale" => "a note"},
          acc
        )

      assert result.success

      assert %{
               entries: [%{day_index: 1, meal_type: "breakfast", items: [%{recipe_id: id}]}],
               rationale: "a note"
             } =
               new_acc.submitted

      assert id == recipe.id
      assert History.list_calendar_user_meals(client.id, today, Date.add(today, 6)) == []
    end

    test "rejects a date before today even inside the plan week" do
      professional = user_fixture()
      client = user_fixture()
      recipe = recipe_fixture(professional, %{title: "past day recipe"})
      today = Date.utc_today()
      yesterday = Date.add(today, -1)

      acc =
        professional.id
        |> NutritionistMealPlanAgent.new_acc(client.id, start_date: Date.add(today, -3))
        |> Map.put(:offered, MapSet.new([recipe.id]))

      {result, new_acc} =
        NutritionistMealPlanAgent.handle_tool(
          "submit_plan",
          %{
            "entries" => [
              %{"date" => Date.to_string(yesterday), "slot" => "Lunch", "recipe_id" => recipe.id}
            ],
            "rationale" => "x"
          },
          acc
        )

      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "outside the plan range"))
      assert new_acc.submitted == nil
    end

    test "rejects a recipe id the search never offered, and an empty plan" do
      professional = user_fixture()
      client = user_fixture()
      recipe = recipe_fixture(professional, %{title: "never searched"})
      today = Date.utc_today()
      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id, start_date: today)

      {result, _} =
        NutritionistMealPlanAgent.handle_tool(
          "submit_plan",
          %{
            "entries" => [
              %{"date" => Date.to_string(today), "slot" => "Lunch", "recipe_id" => recipe.id}
            ],
            "rationale" => "x"
          },
          acc
        )

      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "was not in your search results"))

      {empty, _} =
        NutritionistMealPlanAgent.handle_tool(
          "submit_plan",
          %{"entries" => [], "rationale" => "x"},
          acc
        )

      refute empty.success
    end
  end

  describe "guards — deterministic diet / avoid enforcement from the client file" do
    test "are built from the same resolved context get_client_record returns" do
      professional = user_fixture()
      client = user_fixture()
      put_profile(client.id, %{diet: "pescatarian", avoid_foods: ["Shrimp "]})

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)

      assert acc.guards.diet_mode == :pescatarian
      assert acc.guards.avoid_terms == ["shrimp"]
    end

    test "intake free text is cleaned and kept apart from the curated avoid list" do
      professional = user_fixture()
      client = user_fixture()
      put_profile(client.id, %{avoid_foods: ["Peanuts"]})

      {:ok, record} =
        Professionals.create_client_record(%{
          professional_id: professional.id,
          user_id: client.id,
          full_name: "Free Text"
        })

      {:ok, _intake} =
        Professionals.create_intake(%{
          "professional_client_id" => record.id,
          "details" => %{
            "allergies" => "-",
            "food_intolerances" => "no",
            "food_aversions" => "oil, ham, peanuts"
          }
        })

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)

      # Curated chips stay substring-matched; "peanuts" is not demoted by also
      # appearing in the intake.
      assert acc.guards.avoid_terms == ["peanuts"]
      # "-" and "no" would have matched half the catalog as substrings.
      assert acc.guards.avoid_word_terms == ["oil", "ham"]

      {record_view, _} = NutritionistMealPlanAgent.handle_tool("get_client_record", %{}, acc)
      refute Map.has_key?(record_view, :avoid_free_text)
    end

    test "search_recipes never offers a recipe whose title matches the client's avoid list" do
      professional = user_fixture()
      client = user_fixture()
      put_profile(client.id, %{avoid_foods: ["shrimp"]})

      safe = searchable_recipe(professional, "garlic chicken skewers")
      avoided = searchable_recipe(professional, "garlic shrimp skewers")

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)

      {result, new_acc} =
        NutritionistMealPlanAgent.handle_tool(
          "search_recipes",
          %{"query" => "garlic skewers"},
          acc
        )

      ids = Enum.map(result.recipes, & &1.recipe_id)
      assert safe.id in ids
      refute avoided.id in ids
      # …and it never enters the provenance set, so it cannot be submitted either.
      refute MapSet.member?(new_acc.offered, avoided.id)
    end

    test "search_recipes drops a recipe containing a condition-implicated ingredient" do
      professional = user_fixture()
      client = user_fixture()

      safe = searchable_recipe(professional, "plain rice bowl")
      risky = searchable_recipe(professional, "hidden ingredient bowl")
      [%{ingredient_id: risky_ingredient_id} | _] = risky.recipe_ingredients

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)
      guards = %{acc.guards | avoid_ingredient_ids: MapSet.new([risky_ingredient_id])}

      {result, _acc} =
        NutritionistMealPlanAgent.handle_tool(
          "search_recipes",
          %{"query" => "bowl"},
          %{acc | guards: guards}
        )

      ids = Enum.map(result.recipes, & &1.recipe_id)
      assert safe.id in ids
      refute risky.id in ids
    end
  end

  describe "catalog" do
    test "own recipes first, then saved, then public — never another user's private one" do
      professional = user_fixture()
      client = user_fixture()
      other = user_fixture()

      public = searchable_recipe(other, "public lentil soup qzx")
      saved = searchable_recipe(other, "saved lentil soup qzx")
      own = searchable_recipe(professional, "own lentil soup qzx")
      private = searchable_recipe(other, "private lentil soup qzx")
      Repo.update_all(from(r in Recipe, where: r.id == ^private.id), set: [private: true])
      {:ok, _} = Mehungry.Accounts.UserContent.save_user_recipe(professional.id, saved.id)

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)
      assert acc.guards.catalog == {:user, professional.id}

      {result, _} =
        NutritionistMealPlanAgent.handle_tool(
          "search_recipes",
          %{"query" => "lentil soup qzx"},
          acc
        )

      sources = Map.new(result.recipes, &{&1.recipe_id, &1.source})
      ids = Enum.map(result.recipes, & &1.recipe_id)

      assert sources[own.id] == "own"
      assert sources[saved.id] == "saved"
      refute private.id in ids

      own_at = Enum.find_index(ids, &(&1 == own.id))
      saved_at = Enum.find_index(ids, &(&1 == saved.id))
      assert own_at < saved_at

      # Public recipes come after the own + saved tiers (the public tier is the
      # whole table, so this fixture may rank outside the top-N).
      if public.id in ids do
        assert sources[public.id] == "public"
        assert saved_at < Enum.find_index(ids, &(&1 == public.id))
      end
    end

    test "with no own or saved recipes the search still returns public recipes" do
      professional = user_fixture()
      client = user_fixture()
      other = user_fixture()
      searchable_recipe(other, "public bean stew zzq")

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)

      {result, _} =
        NutritionistMealPlanAgent.handle_tool("search_recipes", %{"query" => "bean stew"}, acc)

      assert result.found
      assert Enum.all?(result.recipes, &(&1.source == "public"))
    end
  end

  describe "get_client_summary" do
    test "sends the model a first name only — no email" do
      professional = user_fixture()
      client = user_fixture()

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)
      {result, _acc} = NutritionistMealPlanAgent.handle_tool("get_client_summary", %{}, acc)

      refute Map.has_key?(result, :email)
      refute inspect(result) =~ client.email
    end
  end

  describe "search_recipes" do
    test "returns per-serving calories derived from the recipe's stored nutrients" do
      professional = user_fixture()
      client = user_fixture()

      recipe =
        recipe_fixture(professional, %{title: "high protein chicken bowl", servings: 2})

      # Set a deterministic nutrients tree + an embedding so the real vector path
      # (via the EmbeddingClientStub seam) ranks this recipe for the query.
      Repo.update_all(
        from(r in Recipe, where: r.id == ^recipe.id),
        set: [
          nutrients: %{"Energy" => %{"amount" => 800.0, "measurement_unit" => "kcal"}},
          embedding: Pgvector.new(EmbeddingClientStub.vector(recipe.title))
        ]
      )

      acc = NutritionistMealPlanAgent.new_acc(professional.id, client.id)

      {result, _acc} =
        NutritionistMealPlanAgent.handle_tool(
          "search_recipes",
          %{"query" => "high protein chicken bowl"},
          acc
        )

      assert result.found
      found = Enum.find(result.recipes, &(&1.recipe_id == recipe.id))
      assert found
      # 800 kcal whole recipe / 2 servings
      assert found.calories == 400
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────────

  # user_fixture already creates a profile — update it in place rather than
  # inserting a duplicate (which would break the one-profile-per-user read).
  defp put_profile(user_id, attrs) do
    from(p in Mehungry.Accounts.UserProfile, where: p.user_id == ^user_id)
    |> Repo.update_all(set: Map.to_list(attrs))
  end

  # A recipe the stubbed embedding search can find by its title.
  defp searchable_recipe(owner, title) do
    recipe = recipe_fixture(owner, %{title: title, servings: 2})

    Repo.update_all(
      from(r in Recipe, where: r.id == ^recipe.id),
      set: [embedding: Pgvector.new(EmbeddingClientStub.vector(title))]
    )

    Repo.preload(recipe, :recipe_ingredients)
  end

  defp assign_meal(user_id, %Date{} = date, meal_type, time) do
    {:ok, start_dt} = NaiveDateTime.new(date, time)
    end_dt = NaiveDateTime.add(start_dt, 3600)

    {:ok, meal} =
      History.create_user_meal(%{
        user_id: user_id,
        meal_type: meal_type,
        title: Mehungry.History.MealType.label(meal_type),
        start_dt: start_dt,
        end_dt: end_dt
      })

    meal
  end
end
