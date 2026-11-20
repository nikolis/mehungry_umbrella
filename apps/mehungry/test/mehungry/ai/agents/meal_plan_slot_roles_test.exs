defmodule Mehungry.AI.Agents.MealPlanSlotRolesTest do
  @moduledoc """
  Deterministic coverage of meal-role enforcement in the shared meal-plan core:
  slot-scoped recipe search (in SQL, before the limit), roles in search
  results, and `submit_plan` rejecting a recipe whose roles don't fit its slot
  (the "Patlıcan Salatası as Dinner" bug). No LLM.
  """
  use Mehungry.DataCase, async: false

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.AI.EmbeddingClientStub
  alias Mehungry.AI.Agents.MealPlanCore
  alias Mehungry.Food.{MealRoleAssignments, Recipe}
  alias Mehungry.Repo
  alias Mehungry.Search.RecipeVectorSearch

  setup do
    user = user_fixture()

    meze = seeded(user, "Patlıcan Salatası smoky eggplant dinner", ["meze", "side"])
    main = seeded(user, "Moussaka eggplant dinner", ["main"])
    unclassified = seeded(user, "Imam bayildi eggplant dinner", nil)
    sauce = seeded(user, "Eggplant dinner sauce", ["component"])

    guards = MealPlanCore.guards(catalog: {:user, user.id}, ingredient_owner_id: user.id)

    %{
      user: user,
      guards: guards,
      meze: meze,
      main: main,
      unclassified: unclassified,
      sauce: sauce
    }
  end

  defp seeded(user, title, roles) do
    recipe = recipe_fixture(user, %{title: title})
    vector = Pgvector.new(EmbeddingClientStub.vector(title))
    Repo.update_all(from(r in Recipe, where: r.id == ^recipe.id), set: [embedding: vector])

    if roles do
      MealRoleAssignments.apply_ai_roles(
        recipe.id,
        Enum.map(roles, &%{role: &1, confidence: 0.9})
      )
    end

    recipe
  end

  defp acc(guards) do
    %{
      guards: guards,
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      start_date: ~D[2026-11-23],
      submitted: nil
    }
  end

  defp ids(results), do: results |> Enum.map(& &1.recipe_id) |> MapSet.new()

  test "RecipeVectorSearch :meal_roles keeps matching + unclassified recipes", ctx do
    found =
      "eggplant dinner"
      |> RecipeVectorSearch.search(user_id: ctx.user.id, meal_roles: ["main", "soup"])
      |> MapSet.new(& &1.id)

    assert MapSet.member?(found, ctx.main.id)
    assert MapSet.member?(found, ctx.unclassified.id)
    refute MapSet.member?(found, ctx.meze.id)
    refute MapSet.member?(found, ctx.sauce.id)
  end

  test "search with a slot only offers dishes that can fill it, with their roles", ctx do
    {%{recipes: recipes}, acc} =
      MealPlanCore.search_recipes_tool("eggplant dinner", acc(ctx.guards), "Dinner")

    assert ids(recipes) == MapSet.new([ctx.main.id, ctx.unclassified.id])
    assert Enum.find(recipes, &(&1.recipe_id == ctx.main.id)).roles == ["main"]
    assert Enum.find(recipes, &(&1.recipe_id == ctx.unclassified.id)).roles == []
    refute MapSet.member?(acc.offered, ctx.meze.id)
  end

  test "search without a slot still shows roles, but never a pure component", ctx do
    {%{recipes: recipes}, _acc} =
      MealPlanCore.search_recipes_tool("eggplant dinner", acc(ctx.guards))

    assert MapSet.member?(ids(recipes), ctx.meze.id)
    refute MapSet.member?(ids(recipes), ctx.sauce.id)
    assert Enum.find(recipes, &(&1.recipe_id == ctx.meze.id)).roles == ["side", "meze"]
  end

  test "submit_plan rejects a meze as Dinner and accepts a main", ctx do
    {_result, acc} = MealPlanCore.search_recipes_tool("eggplant dinner", acc(ctx.guards))

    entry = fn id ->
      %{"date" => "2026-11-23", "slot" => "Dinner", "recipe_id" => id, "cooking_portions" => 1}
    end

    {%{success: false, errors: [error]}, _} =
      MealPlanCore.submit_plan_tool(%{"entries" => [entry.(ctx.meze.id)]}, acc)

    assert error =~ "Patlıcan Salatası"
    assert error =~ "not a main, a dinner dish or a meal soup"
    assert error =~ ~s(slot: "Dinner")

    assert {%{success: true}, _} =
             MealPlanCore.submit_plan_tool(%{"entries" => [entry.(ctx.main.id)]}, acc)

    assert {%{success: true}, _} =
             MealPlanCore.submit_plan_tool(%{"entries" => [entry.(ctx.unclassified.id)]}, acc)
  end

  test "slot_role_errors ignores ingredient entries and unknown recipes" do
    meta = %{1 => %{title: "Tzatziki", roles: ["meze"]}}

    assert MealPlanCore.slot_role_errors(
             [
               %{"date" => "2026-11-23", "slot" => "Lunch", "ingredient_id" => 9},
               %{"date" => "2026-11-23", "slot" => "Lunch", "recipe_id" => 2},
               %{"date" => "2026-11-23", "slot" => "Morning Snack", "recipe_id" => 1}
             ],
             meta
           ) == [
             ~s(2026-11-23 Morning Snack: "Tzatziki" \(recipe_id 1\) is a meze, not a snack, dessert or drink — or better, a whole-food ingredient. Replace it — call the search tool with slot: "Morning Snack" to get dishes that fit.)
           ]
  end
end
