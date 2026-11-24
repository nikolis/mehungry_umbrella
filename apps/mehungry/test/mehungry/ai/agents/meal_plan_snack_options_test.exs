defmodule Mehungry.AI.Agents.MealPlanSnackOptionsTest do
  @moduledoc """
  Phase 3 of the composition rules, without an LLM:

    * `snack_options/3` — curated nuts + curated fruit in season in a country, through
      the run's guards;
    * snack mode vs. the no-nut fallback (`with_snack_options/2`);
    * `list_snack_options` makes exactly those ingredients submittable, and
      `submit_plan` enforces fruit / nut snacks;
    * the nutritionist draft reads the CLIENT's country;
    * slot searches apply the time caps when `:time` is on.
  """
  # Swaps the global :seasonal_availability config — not async.
  use Mehungry.DataCase, async: false

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [ingredient_fixture: 1, recipe_fixture: 2]

  alias Mehungry.AI.Agents.{MealPlanCore, NutritionistMealPlanAgent}
  alias Mehungry.AI.EmbeddingClientStub
  alias Mehungry.Food.{FoundementalFood, MealRoleAssignments, Recipe, SnackIngredients}
  alias Mehungry.{Accounts, Food, Repo}

  # Seasons for the test: species ids in season in IT in July, read from app env.
  defmodule Seasons do
    @behaviour Mehungry.Food.SeasonalAvailability

    @impl true
    def available_species_ids("IT", 7),
      do: Application.get_env(:mehungry, :test_in_season, MapSet.new())

    def available_species_ids(_country, _month), do: MapSet.new()

    @impl true
    def supported_countries,
      do: [%{code: "GR", name: "Greece"}, %{code: "IT", name: "Italy"}]
  end

  setup do
    previous = Application.get_env(:mehungry, :seasonal_availability)
    Application.put_env(:mehungry, :seasonal_availability, Seasons)

    on_exit(fn ->
      Application.delete_env(:mehungry, :test_in_season)

      if previous,
        do: Application.put_env(:mehungry, :seasonal_availability, previous),
        else: Application.delete_env(:mehungry, :seasonal_availability)
    end)

    peach = ingredient_fixture(%{name: "zzsnack peaches"})
    orange = ingredient_fixture(%{name: "zzsnack oranges"})
    almond = ingredient_fixture(%{name: "zzsnack almonds"})
    walnut = ingredient_fixture(%{name: "zzsnack walnuts"})

    peach_species = curate_species(peach, "Peach")
    _orange_species = curate_species(orange, "Orange")
    Application.put_env(:mehungry, :test_in_season, MapSet.new([peach_species]))

    for i <- [peach, orange], do: {:ok, _} = SnackIngredients.add(i.id, "fresh_fruit")
    for i <- [almond, walnut], do: {:ok, _} = SnackIngredients.add(i.id, "dried_nut")

    %{peach: peach, orange: orange, almond: almond, walnut: walnut}
  end

  defp curate_species(ingredient, name) do
    {:ok, species} =
      Food.create_foundemental_species(%{name: "#{name} #{System.unique_integer([:positive])}"})

    Repo.insert!(%FoundementalFood{
      foundemental_species_id: species.id,
      ingredient_id: ingredient.id,
      usda_name: ingredient.name
    })

    species.id
  end

  defp guards(opts \\ []), do: MealPlanCore.guards([catalog: :public] ++ opts)

  defp ids(list), do: MapSet.new(list, & &1.ingredient_id)

  defp base_acc(guards) do
    %{
      start_date: ~D[2030-07-01],
      guards: guards,
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      calorie_band: nil,
      submitted: nil
    }
  end

  describe "snack_options/3" do
    test "fruit in season in that country + every curated nut", ctx do
      options = MealPlanCore.snack_options(guards(), "IT", [7])

      assert ids(options.fruits) == MapSet.new([ctx.peach.id])
      assert ids(options.nuts) == MapSet.new([ctx.almond.id, ctx.walnut.id])
      assert options.fruit_ids == MapSet.new([ctx.peach.id])
      assert [%{units: units} | _] = options.nuts
      assert is_list(units)
    end

    test "another country or month has no fruit", _ctx do
      assert MealPlanCore.snack_options(guards(), "GR", [7]).fruits == []
      assert MealPlanCore.snack_options(guards(), "IT", [1]).fruits == []
    end

    test "a week across a month boundary counts fruit in season in either month", ctx do
      options =
        MealPlanCore.snack_options(
          guards(),
          "IT",
          MealPlanCore.plan_months(~D[2030-06-28], ~D[2030-07-04])
        )

      assert ids(options.fruits) == MapSet.new([ctx.peach.id])
    end

    test "the run's avoid guard removes a curated nut", ctx do
      options = MealPlanCore.snack_options(guards(avoid_terms: ["walnut"]), "IT", [7])
      assert ids(options.nuts) == MapSet.new([ctx.almond.id])
    end
  end

  describe "snack mode" do
    test "with a curated nut: list_snack_options + every rule group" do
      acc =
        guards()
        |> base_acc()
        |> MealPlanCore.with_snack_options(MealPlanCore.snack_options(guards(), "IT", [7]))

      assert MealPlanCore.snack_mode?(acc)
      assert acc.rules == MapSet.new([:composition, :time, :snack_kinds])
      assert MealPlanCore.snack_tool_def(acc).name == "list_snack_options"
    end

    test "no nut available: falls back to the open ingredient search, :snack_kinds off" do
      acc =
        guards()
        |> base_acc()
        |> MealPlanCore.with_snack_options(%{
          fruits: [],
          nuts: [],
          fruit_ids: MapSet.new(),
          nut_ids: MapSet.new()
        })

      refute MealPlanCore.snack_mode?(acc)
      assert acc.rules == MapSet.new([:composition, :time])
      assert MealPlanCore.snack_tool_def(acc).name == "search_ingredients"
      assert {%{error: _}, _} = MealPlanCore.list_snack_options_tool(acc)
    end
  end

  describe "list_snack_options + submit_plan" do
    setup ctx do
      acc =
        guards()
        |> base_acc()
        |> MealPlanCore.with_snack_options(MealPlanCore.snack_options(guards(), "IT", [7]))

      {result, acc} = MealPlanCore.list_snack_options_tool(acc)
      Map.merge(ctx, %{acc: acc, result: result})
    end

    test "returns the options and makes them — and only them — submittable", ctx do
      assert ids(ctx.result.seasonal_fruits) == MapSet.new([ctx.peach.id])
      assert ctx.result.note == nil

      assert ctx.acc.offered_ingredients ==
               MapSet.new([ctx.peach.id, ctx.almond.id, ctx.walnut.id])

      assert Map.has_key?(ctx.acc.ingredient_kcal, ctx.almond.id)
    end

    test "seasonal fruit in the morning and nuts in the afternoon are accepted", ctx do
      entries = [
        snack("Morning Snack", [ctx.peach.id, ctx.almond.id]),
        snack("Afternoon Snack", [ctx.walnut.id])
      ]

      assert {%{success: true}, _} =
               MealPlanCore.submit_plan_tool(%{"entries" => entries}, ctx.acc)
    end

    test "a nut-only morning snack is rejected while fruit is in season", ctx do
      {result, _} =
        MealPlanCore.submit_plan_tool(
          %{"entries" => [snack("Morning Snack", [ctx.almond.id])]},
          ctx.acc
        )

      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "at least one seasonal fruit"))
    end

    test "an out-of-season curated fruit is never offered, so it can't be submitted", ctx do
      {result, _} =
        MealPlanCore.submit_plan_tool(
          %{"entries" => [snack("Morning Snack", [ctx.orange.id, ctx.peach.id])]},
          ctx.acc
        )

      refute result.success

      assert Enum.any?(
               result.errors,
               &(&1 =~ "ingredient_id #{ctx.orange.id} was not in your search results")
             )
    end
  end

  defp snack(slot, ids) do
    %{
      "date" => "2030-07-01",
      "slot" => slot,
      "items" => Enum.map(ids, &%{"ingredient_id" => &1, "quantity" => 1})
    }
  end

  test "a nutritionist draft uses the client's country", ctx do
    professional = user_fixture()
    client = user_fixture()
    profile = Accounts.get_user_profile_by_user_id(client.id)

    {:ok, _} =
      if profile,
        do: Accounts.update_user_profile(profile, %{country: "IT"}),
        else: Accounts.create_user_profile(%{user_id: client.id, country: "IT"})

    acc =
      NutritionistMealPlanAgent.new_acc(professional.id, client.id, start_date: ~D[2030-07-01])

    assert MealPlanCore.snack_mode?(acc)
    assert acc.fruit_ids == MapSet.new([ctx.peach.id])
  end

  describe "slot searches with :time on" do
    setup do
      user = user_fixture()

      %{
        user: user,
        quick: seeded(user, "Quick eggs breakfast plate", 5, 5, ["breakfast"]),
        slow: seeded(user, "Slow eggs breakfast bake", 20, 40, ["breakfast"]),
        stew: seeded(user, "Long eggs dinner stew", 30, 90, ["main"]),
        frittata: seeded(user, "Baked eggs dinner frittata", 20, 45, ["dinner"])
      }
    end

    defp seeded(user, title, prep, cook, roles) do
      recipe = recipe_fixture(user, %{title: title})

      Repo.update_all(from(r in Recipe, where: r.id == ^recipe.id),
        set: [
          embedding: Pgvector.new(EmbeddingClientStub.vector(title)),
          preperation_time_lower_limit: prep,
          cooking_time_lower_limit: cook
        ]
      )

      MealRoleAssignments.apply_ai_roles(
        recipe.id,
        Enum.map(roles, &%{role: &1, confidence: 0.9})
      )

      recipe
    end

    defp found(ctx, slot, rules) do
      acc = %{
        guards: MealPlanCore.guards(catalog: {:user, ctx.user.id}),
        offered: MapSet.new(),
        rules: MapSet.new(rules)
      }

      {result, _} = MealPlanCore.search_recipes_tool("eggs", acc, slot)
      MapSet.new(Map.get(result, :recipes, []), & &1.recipe_id)
    end

    test "Breakfast only offers dishes of ≤ 15 minutes", ctx do
      found = found(ctx, "Breakfast", [:composition, :time])
      assert MapSet.member?(found, ctx.quick.id)
      refute MapSet.member?(found, ctx.slow.id)

      # Without :time the slow one is offered.
      assert MapSet.member?(found(ctx, "Breakfast", [:composition]), ctx.slow.id)
    end

    test "Dinner offers ≤ 40-minute mains and any dinner dish", ctx do
      found = found(ctx, "Dinner", [:composition, :time])
      refute MapSet.member?(found, ctx.stew.id)
      assert MapSet.member?(found, ctx.frittata.id)
    end
  end
end
