defmodule Mehungry.AI.Agents.NutritionistAgentContextTest do
  @moduledoc """
  Deterministic coverage of the client-context tools the NutritionistAgent gained
  so the AI draft actually consumes the nutritionist's file and the assigned plan:

    * get_client_record — merges intake (goal/TDEE), linked conditions, and the
      client's profile (diet/avoid_foods) into one brief, incl. a unified `avoid`
      list and a calorie_target.
    * get_assigned_plan — reads the week's already-assigned calendar meals and
      records their (date, slot) cells into the accumulator.
    * submit_plan — never overwrites an assigned cell (skip-filled-slots).
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
  alias Mehungry.AI.Agents.NutritionistAgent

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

      put_profile(client.id, %{diet: "vegetarian", avoid_foods: ["shrimp"]})

      acc = NutritionistAgent.new_acc(professional.id, client.id)
      {result, ^acc} = NutritionistAgent.handle_tool("get_client_record", %{}, acc)

      assert result.has_record
      assert result.diet == "vegetarian"
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

      acc = NutritionistAgent.new_acc(professional.id, client.id)
      {result, _acc} = NutritionistAgent.handle_tool("get_client_record", %{}, acc)

      assert result.calorie_target == 2200
    end

    test "is safe when the client has no record or profile" do
      professional = user_fixture()
      client = user_fixture()

      acc = NutritionistAgent.new_acc(professional.id, client.id)
      {result, _acc} = NutritionistAgent.handle_tool("get_client_record", %{}, acc)

      refute result.has_record
      assert result.diet == "omnivore"
      assert result.calorie_target == nil
      assert result.avoid == []
      assert result.conditions == []
    end
  end

  describe "get_assigned_plan" do
    test "records occupied (date, slot) cells for the plan week into the accumulator" do
      professional = user_fixture()
      client = user_fixture()

      today = Date.utc_today()
      tomorrow = Date.add(today, 1)

      assign_meal(client.id, today, "breakfast", ~T[08:00:00])
      assign_meal(client.id, tomorrow, "lunch", ~T[13:00:00])

      acc = NutritionistAgent.new_acc(professional.id, client.id)
      {result, new_acc} = NutritionistAgent.handle_tool("get_assigned_plan", %{}, acc)

      assert result.assigned_count == 2
      assert MapSet.member?(new_acc.occupied, {Date.to_string(today), "Breakfast"})
      assert MapSet.member?(new_acc.occupied, {Date.to_string(tomorrow), "Lunch"})
    end

    test "reports no assignments and an empty occupied set for a fresh week" do
      professional = user_fixture()
      client = user_fixture()

      acc = NutritionistAgent.new_acc(professional.id, client.id)
      {result, new_acc} = NutritionistAgent.handle_tool("get_assigned_plan", %{}, acc)

      assert result.assigned_count == 0
      assert MapSet.size(new_acc.occupied) == 0
    end
  end

  describe "submit_plan" do
    test "skips cells already assigned by the nutritionist and persists only empty ones" do
      professional = user_fixture()
      client = user_fixture()
      recipe = recipe_fixture(professional, %{title: "test recipe", servings: 2})

      today = Date.utc_today()
      tomorrow = Date.add(today, 1)

      acc =
        professional.id
        |> NutritionistAgent.new_acc(client.id)
        |> Map.put(:offered, MapSet.new([recipe.id]))
        |> Map.put(:occupied, MapSet.new([{Date.to_string(today), "Breakfast"}]))

      entries = [
        %{
          "date" => Date.to_string(today),
          "slot" => "Breakfast",
          "recipe_id" => recipe.id,
          "cooking_portions" => 2
        },
        %{
          "date" => Date.to_string(tomorrow),
          "slot" => "Lunch",
          "recipe_id" => recipe.id,
          "cooking_portions" => 2
        }
      ]

      {result, new_acc} =
        NutritionistAgent.handle_tool(
          "submit_plan",
          %{"entries" => entries, "rationale" => "test"},
          acc
        )

      assert result.success
      assert result.created == 1
      assert result.left_assigned == 1
      assert new_acc.submitted == {:plan_created, 1}
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

      acc = NutritionistAgent.new_acc(professional.id, client.id)

      {result, _acc} =
        NutritionistAgent.handle_tool(
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
