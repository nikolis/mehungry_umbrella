defmodule Mehungry.AI.Agents.MealPlanCompositeTest do
  @moduledoc """
  `submit_plan` over composite meals (a slot holding several items): validation,
  normalization, balancing with fixed salad/dessert parts, coordinate descent on a
  big day, and the fill-gaps fix — cells already on the calendar are dropped before
  calories are counted, so they are never counted twice. No LLM, no catalog.
  """
  use Mehungry.DataCase, async: true

  alias Mehungry.AI.Agents.MealPlanCore

  @day ~D[2030-01-07]
  @date "2030-01-07"
  @band %{min: 1796, max: 2195, aim: 1995, basis: :goal_maintain}

  defp acc(overrides \\ %{}) do
    Map.merge(
      %{
        start_date: @day,
        offered: MapSet.new([1, 2, 3, 4, 5]),
        offered_ingredients: MapSet.new(),
        recipe_meta: %{
          1 => %{title: "Eggs", roles: ["breakfast"], calories: 300},
          2 => %{title: "Stew", roles: ["main"], calories: 600},
          3 => %{title: "Soup", roles: ["soup"], calories: 350},
          4 => %{title: "Greek salad", roles: ["salad"], calories: 150},
          5 => %{title: "Baklava", roles: ["dessert"], calories: 250}
        },
        calorie_band: nil,
        submitted: nil
      },
      overrides
    )
  end

  defp recipe(id, part \\ "main", servings \\ 1),
    do: %{"recipe_id" => id, "part" => part, "cooking_portions" => 2, "servings" => servings}

  defp submit(entries, acc), do: MealPlanCore.submit_plan_tool(%{"entries" => entries}, acc)

  defp composite_day(lunch_servings \\ 1) do
    [
      %{"date" => @date, "slot" => "Breakfast", "items" => [recipe(1)]},
      %{
        "date" => @date,
        "slot" => "Lunch",
        "items" => [recipe(2, "main", lunch_servings), recipe(4, "salad"), recipe(5, "dessert")]
      },
      %{"date" => @date, "slot" => "Dinner", "items" => [recipe(3)]}
    ]
  end

  test "a lunch of main + salad + dessert is accepted and normalized as one meal" do
    {result, acc} = submit(composite_day(), acc())

    assert result.success
    lunch = Enum.find(acc.submitted.entries, &(&1.meal_type == "lunch"))

    assert [
             %{recipe_id: 2, part: "main"},
             %{recipe_id: 4, part: "salad"},
             %{recipe_id: 5, part: "dessert"}
           ] =
             lunch.items

    assert lunch.day_index == 1
  end

  test "composition errors come back to the model" do
    bad = [%{"date" => @date, "slot" => "Dinner", "items" => [recipe(3), recipe(4, "salad")]}]
    {result, acc} = submit(bad, acc())

    refute result.success
    assert Enum.any?(result.errors, &(&1 =~ "Dinner is a single recipe"))
    assert acc.submitted == nil
  end

  test "an empty meal is rejected" do
    {result, _} = submit([%{"date" => @date, "slot" => "Lunch", "items" => []}], acc())
    refute result.success
    assert Enum.any?(result.errors, &(&1 =~ "has no items"))
  end

  test "an item id the search never offered is rejected (provenance per item)" do
    entries = [%{"date" => @date, "slot" => "Lunch", "items" => [recipe(2), recipe(99, "salad")]}]
    {result, _} = submit(entries, acc())
    refute result.success
    assert Enum.any?(result.errors, &(&1 =~ "recipe_id 99 was not in your search results"))
  end

  describe "balancing" do
    test "the main's servings move; the salad and dessert stay put" do
      # 300 + (600 + 150 + 250) + 350 = 1,650: under 1,796.
      {result, acc} = submit(composite_day(), acc(%{calorie_band: @band}))

      assert result.success
      lunch = Enum.find(acc.submitted.entries, &(&1.meal_type == "lunch"))

      assert [
               %{part: "main", servings: main},
               %{part: "salad", servings: 1},
               %{part: "dessert", servings: 1}
             ] =
               lunch.items

      total =
        for e <- acc.submitted.entries, item <- e.items, reduce: 0 do
          sum -> sum + acc.recipe_meta[item.recipe_id].calories * item.servings
        end

      assert total in 1796..2195
      assert main >= 1
    end

    test "a big day (beyond exhaustive search) is still brought into the band" do
      # Ten real snack ingredients in a real gram unit, 6 kcal per gram.
      gram = Mehungry.FoodFixtures.measurement_unit_fixture()

      ids =
        for n <- 1..10,
            do: Mehungry.FoodFixtures.ingredient_fixture(%{name: "zzbig snack #{n}"}).id

      acc =
        acc(%{
          calorie_band: @band,
          offered_ingredients: MapSet.new(ids),
          ingredient_kcal: Map.new(ids, &{&1, %{gram.id => 6.0}})
        })

      # 20 g each = 120 kcal × 10 = 1,200 of snacks; each gram quantity has 5
      # options, so 5^10 × 2 × 3 × 3 combos — far past the exhaustive limit,
      # which exercises coordinate descent.
      snack = fn slot, slot_ids ->
        %{
          "date" => @date,
          "slot" => slot,
          "items" =>
            Enum.map(
              slot_ids,
              &%{"ingredient_id" => &1, "unit_selection" => gram.id, "quantity" => 20}
            )
        }
      end

      {morning, afternoon} = Enum.split(ids, 5)

      # Recipes at two servings: 600 + 1,200 + 700 = 2,500; + 1,200 = 3,700 → over.
      day = [
        %{"date" => @date, "slot" => "Breakfast", "items" => [recipe(1, "main", 2)]},
        %{"date" => @date, "slot" => "Lunch", "items" => [recipe(2, "main", 2)]},
        %{"date" => @date, "slot" => "Dinner", "items" => [recipe(3, "main", 2)]},
        snack.("Morning Snack", morning),
        snack.("Afternoon Snack", afternoon)
      ]

      {result, acc} = submit(day, acc)
      assert result.success

      total =
        for e <- acc.submitted.entries, item <- e.items, reduce: 0 do
          sum ->
            case item do
              %{recipe_id: id} -> sum + acc.recipe_meta[id].calories * item.servings
              %{ingredient_id: _} -> sum + 6 * item.quantity
            end
        end

      assert round(total) in 1796..2195
    end
  end

  describe "fill-gaps: occupied cells" do
    test "an entry for a filled cell is dropped before calories are counted" do
      # Lunch is already on the calendar (800 kcal). The model plans it anyway at
      # 600: counting both would see 300 + 600 + 350 + 800 = 2,050 and leave the
      # rest alone; dropping it sees 300 + 350 + 800 = 1,450 and raises servings.
      acc =
        acc(%{
          calorie_band: @band,
          existing_day_kcal: %{@date => 800},
          occupied_cells: MapSet.new([{@date, "Lunch"}])
        })

      day = [
        %{"date" => @date, "slot" => "Breakfast", "items" => [recipe(1)]},
        %{"date" => @date, "slot" => "Lunch", "items" => [recipe(2)]},
        %{"date" => @date, "slot" => "Dinner", "items" => [recipe(3)]}
      ]

      {result, acc} = submit(day, acc)

      assert result.success
      assert result.message =~ "1 meal(s) in already-filled cells were left out"

      assert Enum.map(acc.submitted.entries, & &1.meal_type) |> Enum.sort() == [
               "breakfast",
               "dinner"
             ]

      planned =
        for e <- acc.submitted.entries, item <- e.items, reduce: 0 do
          sum -> sum + acc.recipe_meta[item.recipe_id].calories * item.servings
        end

      assert (planned + 800) in 1796..2195
    end

    test "a plan made only of filled cells says so" do
      acc = acc(%{occupied_cells: MapSet.new([{@date, "Lunch"}])})
      {result, _} = submit([%{"date" => @date, "slot" => "Lunch", "items" => [recipe(2)]}], acc)

      refute result.success
      assert hd(result.errors) =~ "already filled"
    end
  end

  test "composition_block/1 describes the slots for the enabled groups" do
    block = MealPlanCore.composition_block()
    assert block =~ ~s(part "salad")
    assert block =~ "search_ingredients"
    refute block =~ "15 minutes"

    full = MealPlanCore.composition_block(MapSet.new([:composition, :time, :snack_kinds]))
    assert full =~ "at most 15 minutes"
    assert full =~ "at most 40"
    assert full =~ "list_snack_options"
    assert full =~ "seasonal fruit"
  end
end
