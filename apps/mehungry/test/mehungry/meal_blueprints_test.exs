defmodule Mehungry.MealBlueprintsTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.Blueprint
  alias Mehungry.History.MealType

  defp create_default(user, name \\ "My Blueprint") do
    MealBlueprints.create_blueprint(MealBlueprints.default_blueprint_attrs(user.id, name))
  end

  describe "default_blueprint_attrs/2" do
    test "builds exactly 7 days x the canonical meal slots" do
      user = user_fixture()
      attrs = MealBlueprints.default_blueprint_attrs(user.id, "Cutting week")

      assert length(attrs.days) == 7
      assert Enum.map(attrs.days, & &1.day_index) == Enum.to_list(1..7)

      for day <- attrs.days do
        assert Enum.map(day.meals, & &1.meal_type) == MealType.values()
      end
    end
  end

  describe "create_blueprint/1" do
    test "persists the full 7 x 5 tree" do
      user = user_fixture()
      assert {:ok, %Blueprint{} = bp} = create_default(user)

      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      assert length(loaded.days) == 7
      assert Enum.all?(loaded.days, &(length(&1.meals) == length(MealType.values())))
    end

    test "rejects a tree that is not 7 days" do
      user = user_fixture()

      attrs = %{
        user_id: user.id,
        name: "Short",
        days: [%{day_index: 1, meals: [%{meal_type: "breakfast"}]}]
      }

      assert {:error, changeset} = MealBlueprints.create_blueprint(attrs)
      assert %{days: _} = errors_on(changeset)
    end

    test "rejects an out-of-range day_index" do
      user = user_fixture()
      attrs = MealBlueprints.default_blueprint_attrs(user.id, "Bad day")
      attrs = put_in(attrs, [:days, Access.at(0), :day_index], 8)

      assert {:error, changeset} = MealBlueprints.create_blueprint(attrs)
      refute changeset.valid?
    end

    test "rejects an unsupported meal_type" do
      user = user_fixture()
      attrs = MealBlueprints.default_blueprint_attrs(user.id, "Brunch club")
      attrs = put_in(attrs, [:days, Access.at(0), :meals, Access.at(0), :meal_type], "brunch")

      assert {:error, changeset} = MealBlueprints.create_blueprint(attrs)
      refute changeset.valid?
    end

    test "rejects a macro split that does not total 100%" do
      user = user_fixture()
      attrs = MealBlueprints.default_blueprint_attrs(user.id, "Bad split")

      attrs =
        update_in(attrs, [:days, Access.at(0), :meals, Access.at(0)], fn meal ->
          Map.merge(meal, %{protein_pct: 25, carbs_pct: 40, fats_pct: 30})
        end)

      assert {:error, changeset} = MealBlueprints.create_blueprint(attrs)
      refute changeset.valid?
    end

    test "accepts a macro split that totals 100%" do
      user = user_fixture()
      attrs = MealBlueprints.default_blueprint_attrs(user.id, "Good split")

      attrs =
        update_in(attrs, [:days, Access.at(0), :meals, Access.at(0)], fn meal ->
          Map.merge(meal, %{protein_pct: 40, carbs_pct: 35, fats_pct: 25})
        end)

      assert {:ok, bp} = MealBlueprints.create_blueprint(attrs)

      first_meal =
        MealBlueprints.get_blueprint!(user.id, bp.id).days |> hd() |> Map.fetch!(:meals) |> hd()

      assert {first_meal.protein_pct, first_meal.carbs_pct, first_meal.fats_pct} == {40, 35, 25}
    end

    test "rejects a negative macro percentage" do
      user = user_fixture()
      attrs = MealBlueprints.default_blueprint_attrs(user.id, "Neg carbs")

      attrs =
        update_in(attrs, [:days, Access.at(0), :meals, Access.at(0)], fn meal ->
          Map.merge(meal, %{protein_pct: 130, carbs_pct: -30, fats_pct: 0})
        end)

      assert {:error, changeset} = MealBlueprints.create_blueprint(attrs)
      refute changeset.valid?
    end

    test "defaults the meal macro split to 30/40/30" do
      user = user_fixture()
      {:ok, bp} = create_default(user)

      first_meal =
        MealBlueprints.get_blueprint!(user.id, bp.id).days |> hd() |> Map.fetch!(:meals) |> hd()

      assert {first_meal.protein_pct, first_meal.carbs_pct, first_meal.fats_pct} == {30, 40, 30}
    end

    test "trims, dedups and drops blank blueprint-level tag arrays" do
      user = user_fixture()

      attrs =
        MealBlueprints.default_blueprint_attrs(user.id, "Tags")
        |> Map.merge(%{
          preferred_foods: [" nuts ", "", "dairy"],
          required_nutrients: ["Vitamin C", "Vitamin C", "  "],
          avoid_nutrients: [" Sodium "],
          required_compounds: [" Polyphenols "],
          avoid_compounds: ["Oxalate", ""]
        })

      assert {:ok, bp} = MealBlueprints.create_blueprint(attrs)
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      assert loaded.preferred_foods == ["nuts", "dairy"]
      assert loaded.required_nutrients == ["Vitamin C"]
      assert loaded.avoid_nutrients == ["Sodium"]
      assert loaded.required_compounds == ["Polyphenols"]
      assert loaded.avoid_compounds == ["Oxalate"]
    end

    test "recommended_compounds_for_condition buckets by recommendation direction" do
      {:ok, condition} = Mehungry.Health.create_condition(%{name: "IBS"})

      {:ok, good} =
        Mehungry.Food.create_compound(%{name: "Curcumin", compound_type: "polyphenol"})

      {:ok, bad} = Mehungry.Food.create_compound(%{name: "Fructan", compound_type: "fodmap"})

      {:ok, _} =
        Mehungry.Health.add_recommendation(condition.id, good.id, %{
          recommendation: "encourage",
          source: "manual",
          source_reference: %{"label" => "Clinical note", "url" => "https://example.org"}
        })

      {:ok, _} =
        Mehungry.Health.add_recommendation(condition.id, bad.id, %{
          recommendation: "avoid",
          source: "manual",
          source_reference: %{"label" => "Clinical note", "url" => "https://example.org"}
        })

      assert %{required: ["Curcumin"], avoid: ["Fructan"]} =
               MealBlueprints.recommended_compounds_for_condition(condition.id)

      assert %{required: [], avoid: []} =
               MealBlueprints.recommended_compounds_for_condition(nil)
    end

    test "recommended_nutrients_for_condition buckets by recommendation direction" do
      {:ok, condition} = Mehungry.Health.create_condition(%{name: "Anti-Inflammatory"})

      ref = %{"label" => "Guideline", "url" => "https://example.org"}

      {:ok, _} =
        Mehungry.Health.add_nutrient_recommendation(condition.id, "Omega-3", %{
          recommendation: "encourage",
          source: "guideline",
          source_reference: ref
        })

      {:ok, _} =
        Mehungry.Health.add_nutrient_recommendation(condition.id, "Saturated Fat", %{
          recommendation: "limit",
          source: "guideline",
          source_reference: ref
        })

      assert %{required: ["Omega-3"], avoid: ["Saturated Fat"]} =
               MealBlueprints.recommended_nutrients_for_condition(condition.id)

      assert %{required: [], avoid: []} =
               MealBlueprints.recommended_nutrients_for_condition(nil)
    end

    test "stores an optional blueprint-level condition" do
      user = user_fixture()
      {:ok, condition} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})

      attrs =
        MealBlueprints.default_blueprint_attrs(user.id, "UC Weekly")
        |> Map.put(:condition_id, condition.id)

      assert {:ok, bp} = MealBlueprints.create_blueprint(attrs)
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      assert loaded.condition_id == condition.id
      assert loaded.condition.name == "Ulcerative Colitis"
    end
  end

  describe "get_blueprint!/2" do
    test "is scoped to the owner" do
      owner = user_fixture()
      other = user_fixture()
      {:ok, bp} = create_default(owner)

      assert_raise Ecto.NoResultsError, fn ->
        MealBlueprints.get_blueprint!(other.id, bp.id)
      end
    end

    test "orders meals by canonical slot order" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

      for day <- loaded.days do
        assert Enum.map(day.meals, & &1.meal_type) == MealType.values()
      end
    end
  end

  # Full-tree params, as the editor form submits them (all days + meals, keyed
  # by string index with row ids so cast_assoc updates in place).
  defp full_params(blueprint) do
    days =
      blueprint.days
      |> Enum.with_index()
      |> Map.new(fn {day, di} ->
        meals =
          day.meals
          |> Enum.with_index()
          |> Map.new(fn {meal, mi} ->
            {to_string(mi), %{"id" => to_string(meal.id), "meal_type" => meal.meal_type}}
          end)

        {to_string(di),
         %{"id" => to_string(day.id), "day_index" => day.day_index, "meals" => meals}}
      end)

    %{"days" => days}
  end

  describe "update_blueprint/2" do
    test "edits a nested meal field" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)

      params =
        full_params(loaded)
        |> put_in(["days", "0", "meals", "0", "protein_pct"], "35")
        |> put_in(["days", "0", "meals", "0", "carbs_pct"], "40")
        |> put_in(["days", "0", "meals", "0", "fats_pct"], "25")

      assert {:ok, _} = MealBlueprints.update_blueprint(loaded, params)
      reloaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      first_meal = reloaded.days |> hd() |> Map.fetch!(:meals) |> hd()
      assert first_meal.protein_pct == 35
      assert first_meal.carbs_pct == 40
      assert first_meal.fats_pct == 25
    end
  end

  describe "duplicate_blueprint/2" do
    test "deep-copies with new ids and a 'Copy of' name" do
      user = user_fixture()
      {:ok, bp} = create_default(user, "Maintenance")
      source = MealBlueprints.get_blueprint!(user.id, bp.id)

      assert {:ok, copy} = MealBlueprints.duplicate_blueprint(source)
      assert copy.id != source.id
      assert copy.name == "Copy of Maintenance"

      loaded_copy = MealBlueprints.get_blueprint!(user.id, copy.id)
      assert length(loaded_copy.days) == 7
      assert Enum.all?(loaded_copy.days, &(length(&1.meals) == length(MealType.values())))

      source_meal_ids =
        source.days |> Enum.flat_map(& &1.meals) |> Enum.map(& &1.id) |> MapSet.new()

      copy_meal_ids = loaded_copy.days |> Enum.flat_map(& &1.meals) |> Enum.map(& &1.id)
      assert Enum.all?(copy_meal_ids, &(not MapSet.member?(source_meal_ids, &1)))
    end
  end

  describe "delete_blueprint/1" do
    test "cascades to days and meals" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      day_id = hd(loaded.days).id

      assert {:ok, _} = MealBlueprints.delete_blueprint(loaded)
      assert MealBlueprints.list_blueprints_for_user(user.id) == []
      refute Repo.get(Mehungry.MealBlueprints.BlueprintDay, day_id)
    end
  end

  describe "list_blueprints_for_user/1" do
    test "returns only the user's blueprints, newest first" do
      user = user_fixture()
      other = user_fixture()
      {:ok, _a} = create_default(user, "A")
      {:ok, _b} = create_default(user, "B")
      {:ok, _c} = create_default(other, "C")

      names = user.id |> MealBlueprints.list_blueprints_for_user() |> Enum.map(& &1.name)
      assert "A" in names and "B" in names
      refute "C" in names
    end
  end

  describe "generated plans" do
    defp plan_attrs(user, bp, overrides \\ %{}) do
      Map.merge(
        %{
          name: "Plan A",
          start_date: Date.utc_today(),
          status: "generating",
          blueprint_id: bp.id,
          user_id: user.id
        },
        overrides
      )
    end

    test "create_plan/1 records an in-flight run" do
      user = user_fixture()
      {:ok, bp} = create_default(user)

      assert {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      assert plan.status == "generating"
      assert plan.meals_count == 0
    end

    test "list_plans_for_blueprint/2 scopes to owner + blueprint, newest first" do
      user = user_fixture()
      other = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, other_bp} = create_default(other, "Other")

      {:ok, _a} = MealBlueprints.create_plan(plan_attrs(user, bp, %{name: "A"}))
      {:ok, _b} = MealBlueprints.create_plan(plan_attrs(user, bp, %{name: "B"}))
      {:ok, _c} = MealBlueprints.create_plan(plan_attrs(other, other_bp, %{name: "C"}))

      names =
        user.id
        |> MealBlueprints.list_plans_for_blueprint(bp.id)
        |> Enum.map(& &1.name)

      assert "A" in names and "B" in names
      refute "C" in names
    end

    defp recipe_entry(recipe, overrides \\ %{}) do
      Map.merge(
        %{
          day_index: 1,
          meal_type: "breakfast",
          recipe_id: recipe.id,
          cooking_portions: 2,
          ingredient_id: nil,
          quantity: nil,
          measurement_unit_id: nil,
          ingredient_portion_id: nil
        },
        overrides
      )
    end

    defp ingredient_entry(ingredient, mu, overrides \\ %{}) do
      Map.merge(
        %{
          day_index: 1,
          meal_type: "morning_snack",
          recipe_id: nil,
          cooking_portions: nil,
          ingredient_id: ingredient.id,
          quantity: 30.0,
          measurement_unit_id: mu.id,
          ingredient_portion_id: nil
        },
        overrides
      )
    end

    test "store_plan_meals/2 stores independent plan rows and completes the run" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)

      assert {:ok, plan} =
               MealBlueprints.store_plan_meals(plan, [
                 recipe_entry(recipe, %{day_index: 1}),
                 recipe_entry(recipe, %{day_index: 2, meal_type: "lunch"})
               ])

      assert plan.status == "completed"
      assert plan.meals_count == 2

      # No calendar meals were created.
      assert Mehungry.History.list_history_user_meals_for_user(user.id) == []

      [loaded] = MealBlueprints.list_plans_for_blueprint(user.id, bp.id)
      assert length(loaded.meals) == 2
      assert Enum.map(loaded.meals, & &1.day_index) == [1, 2]
      refute MealBlueprints.plan_imported?(loaded)
    end

    test "list_plan_meals preloads recipe and ingredient for display" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)
      ingredient = ingredient_fixture(%{name: "Almonds"})
      mu = measurement_unit_fixture()

      {:ok, _plan} =
        MealBlueprints.store_plan_meals(plan, [
          recipe_entry(recipe),
          ingredient_entry(ingredient, mu)
        ])

      meals = MealBlueprints.list_plan_meals(plan.id)
      recipe_row = Enum.find(meals, &(&1.recipe_id == recipe.id))
      ingredient_row = Enum.find(meals, &(&1.recipe_id == nil))
      [child] = ingredient_row.ingredients

      assert recipe_row.recipe.title == recipe.title
      assert child.ingredient.id == ingredient.id
      assert child.ingredient.name == "Almonds"
      assert child.measurement_unit.id == mu.id
    end

    test "import_plan_to_calendar/3 creates calendar meals tagged to the plan and marks imported" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)
      ingredient = ingredient_fixture()
      mu = measurement_unit_fixture()

      {:ok, _plan} =
        MealBlueprints.store_plan_meals(plan, [
          recipe_entry(recipe, %{day_index: 1}),
          ingredient_entry(ingredient, mu, %{day_index: 3})
        ])

      start_date = ~D[2026-10-05]
      assert {:ok, 2, 0, 0} = MealBlueprints.import_plan_to_calendar(user.id, plan, start_date)

      user_meals = Mehungry.History.list_history_user_meals_for_user(user.id)
      assert length(user_meals) == 2
      # Day 3 lands on start_date + 2.
      dates = user_meals |> Enum.map(&NaiveDateTime.to_date(&1.start_dt)) |> Enum.sort()
      assert dates == [~D[2026-10-05], ~D[2026-10-07]]
      assert Enum.all?(user_meals, &(&1.blueprint_plan_id == plan.id))

      reloaded = MealBlueprints.get_plan!(user.id, plan.id)
      assert MealBlueprints.plan_imported?(reloaded)
    end

    test "import_plan_to_calendar/3 allows re-import onto another week" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)

      {:ok, _plan} = MealBlueprints.store_plan_meals(plan, [recipe_entry(recipe)])

      assert {:ok, 1, 0, 0} =
               MealBlueprints.import_plan_to_calendar(user.id, plan, ~D[2026-10-05])

      assert {:ok, 1, 0, 0} =
               MealBlueprints.import_plan_to_calendar(user.id, plan, ~D[2026-10-12])

      assert length(Mehungry.History.list_history_user_meals_for_user(user.id)) == 2
    end

    test "import_plan_to_calendar/3 clears meals already in the target week" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)

      {:ok, _plan} =
        MealBlueprints.store_plan_meals(plan, [
          recipe_entry(recipe, %{day_index: 1}),
          recipe_entry(recipe, %{day_index: 4})
        ])

      # A pre-existing meal inside the target week (start 2026-10-05, day 3).
      {:ok, _existing} =
        Mehungry.History.create_user_meal(%{
          title: "Old meal",
          meal_type: "lunch",
          start_dt: ~N[2026-10-07 12:00:00],
          user_id: user.id
        })

      # ...and one outside the week, which must survive.
      {:ok, _outside} =
        Mehungry.History.create_user_meal(%{
          title: "Next week",
          meal_type: "lunch",
          start_dt: ~N[2026-10-20 12:00:00],
          user_id: user.id
        })

      assert {:ok, 2, 0, 1} =
               MealBlueprints.import_plan_to_calendar(user.id, plan, ~D[2026-10-05])

      titles =
        Mehungry.History.list_history_user_meals_for_user(user.id)
        |> Enum.map(& &1.title)

      refute "Old meal" in titles
      assert "Next week" in titles
      assert length(titles) == 3
    end

    test "import re-import onto the same week replaces the prior plan's meals" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)

      {:ok, _plan} =
        MealBlueprints.store_plan_meals(plan, [
          recipe_entry(recipe, %{day_index: 1}),
          recipe_entry(recipe, %{day_index: 2})
        ])

      assert {:ok, 2, 0, 0} =
               MealBlueprints.import_plan_to_calendar(user.id, plan, ~D[2026-10-05])

      # Same week again — the 2 prior meals are cleared, then 2 written afresh.
      assert {:ok, 2, 0, 2} =
               MealBlueprints.import_plan_to_calendar(user.id, plan, ~D[2026-10-05])

      assert length(Mehungry.History.list_history_user_meals_for_user(user.id)) == 2
    end

    test "deleting a blueprint cascades its plans" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, _plan} = MealBlueprints.create_plan(plan_attrs(user, bp))

      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      assert {:ok, _} = MealBlueprints.delete_blueprint(loaded)
      assert MealBlueprints.list_plans_for_blueprint(user.id, bp.id) == []
    end

    test "blueprint_preferences/1 distills targets into a brief" do
      user = user_fixture()

      {:ok, bp} =
        MealBlueprints.create_blueprint(
          MealBlueprints.default_blueprint_attrs(user.id, "Cutting week")
          |> Map.put(:required_nutrients, ["Protein"])
          |> Map.put(:preferred_foods, ["salmon"])
        )

      prefs = MealBlueprints.blueprint_preferences(bp)
      assert prefs =~ "Cutting week"
      assert prefs =~ "Protein"
      assert prefs =~ "salmon"
    end
  end

  describe "visibility & slug" do
    test "defaults to private with no slug" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      assert bp.visibility == "private"
    end

    test "making a blueprint public generates a slug" do
      user = user_fixture()
      {:ok, bp} = create_default(user, "Mediterranean Reset")
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      {:ok, public} = MealBlueprints.update_blueprint(loaded, %{visibility: "public"})

      assert public.visibility == "public"
      assert is_binary(public.slug)
      assert public.slug =~ "mediterranean-reset"
    end

    test "distinct blueprints get distinct slugs" do
      user = user_fixture()
      {:ok, a} = create_default(user, "Same Name")
      {:ok, b} = create_default(user, "Same Name")

      {:ok, a} =
        MealBlueprints.update_blueprint(MealBlueprints.get_blueprint!(user.id, a.id), %{
          visibility: "public"
        })

      {:ok, b} =
        MealBlueprints.update_blueprint(MealBlueprints.get_blueprint!(user.id, b.id), %{
          visibility: "public"
        })

      assert a.slug != b.slug
    end

    test "rejects an unknown visibility" do
      user = user_fixture()
      {:ok, bp} = create_default(user)

      assert {:error, changeset} =
               MealBlueprints.update_blueprint(
                 MealBlueprints.get_blueprint!(user.id, bp.id),
                 %{visibility: "unlisted"}
               )

      refute changeset.valid?
    end
  end

  describe "public reads" do
    defp make_public(user, name) do
      {:ok, bp} = create_default(user, name)

      {:ok, public} =
        MealBlueprints.update_blueprint(MealBlueprints.get_blueprint!(user.id, bp.id), %{
          visibility: "public"
        })

      public
    end

    test "get_public_blueprint_by_slug!/1 returns a public blueprint" do
      user = user_fixture()
      public = make_public(user, "Public One")

      found = MealBlueprints.get_public_blueprint_by_slug!(public.slug)
      assert found.id == public.id
      assert length(found.days) == 7
    end

    test "get_public_blueprint_by_slug!/1 raises for a private blueprint" do
      user = user_fixture()
      {:ok, bp} = create_default(user, "Private One")
      # force a slug without publishing
      {:ok, _} =
        MealBlueprints.update_blueprint(MealBlueprints.get_blueprint!(user.id, bp.id), %{
          description: "x"
        })

      assert_raise Ecto.NoResultsError, fn ->
        MealBlueprints.get_public_blueprint_by_slug!("does-not-exist")
      end
    end

    test "search_public_blueprints/2 filters by title, only public" do
      user = user_fixture()
      _a = make_public(user, "High Protein Week")
      _b = make_public(user, "Low Carb Week")
      {:ok, _priv} = create_default(user, "High Protein Secret")

      names = MealBlueprints.search_public_blueprints("protein") |> Enum.map(& &1.name)
      assert "High Protein Week" in names
      refute "Low Carb Week" in names
      refute "High Protein Secret" in names
    end
  end

  describe "saved blueprints" do
    test "save / list / remove round-trip, scoped per user" do
      owner = user_fixture()
      saver = user_fixture()
      public = make_public(owner, "Shareable")

      assert {:ok, _} = MealBlueprints.save_blueprint_for_user(saver.id, public.id)
      assert MealBlueprints.blueprint_saved?(saver.id, public.id)
      assert [%{id: id}] = MealBlueprints.list_saved_blueprints_for_user(saver.id)
      assert id == public.id
      assert MealBlueprints.list_saved_blueprints_for_user(owner.id) == []

      MealBlueprints.remove_saved_blueprint_for_user(saver.id, public.id)
      refute MealBlueprints.blueprint_saved?(saver.id, public.id)
    end

    test "saving is idempotent" do
      owner = user_fixture()
      saver = user_fixture()
      public = make_public(owner, "Shareable Two")

      {:ok, _} = MealBlueprints.save_blueprint_for_user(saver.id, public.id)
      assert {:ok, _} = MealBlueprints.save_blueprint_for_user(saver.id, public.id)
      assert length(MealBlueprints.list_saved_blueprints_for_user(saver.id)) == 1
    end
  end

  describe "get_blueprint_for_generation/2" do
    test "allows owned, saved, and public; blocks foreign private" do
      owner = user_fixture()
      stranger = user_fixture()

      {:ok, owned} = create_default(owner, "Owned")
      public = make_public(owner, "Public")

      # stranger can reach public
      assert MealBlueprints.get_blueprint_for_generation(stranger.id, public.id).id == public.id
      # owner can reach their own private
      assert MealBlueprints.get_blueprint_for_generation(owner.id, owned.id).id == owned.id

      # stranger cannot reach owner's private
      assert_raise Ecto.NoResultsError, fn ->
        MealBlueprints.get_blueprint_for_generation(stranger.id, owned.id)
      end

      # once saved, a public one is reachable (already public, but confirm save path too)
      {:ok, _} = MealBlueprints.save_blueprint_for_user(stranger.id, public.id)
      assert MealBlueprints.get_blueprint_for_generation(stranger.id, public.id).id == public.id
    end
  end

  describe "plan-meal editing" do
    test "update_plan_meal/2 swaps a recipe slot to a different recipe" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)
      other = recipe_fixture(user)

      {:ok, _} = MealBlueprints.store_plan_meals(plan, [recipe_entry(recipe)])
      [meal] = MealBlueprints.list_plan_meals(plan.id)

      {:ok, {updated, _plan}} =
        MealBlueprints.update_plan_meal(meal, %{recipe_id: other.id, cooking_portions: 3})

      assert updated.recipe_id == other.id
      assert updated.cooking_portions == 3
    end

    test "update_plan_meal/2 gives a meal several ingredients (recipe kept)" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)
      mu = measurement_unit_fixture()
      rice = ingredient_fixture(%{name: "Brown rice"})
      yogurt = ingredient_fixture(%{name: "Yogurt"})

      {:ok, _} = MealBlueprints.store_plan_meals(plan, [recipe_entry(recipe)])
      [meal] = MealBlueprints.list_plan_meals(plan.id)

      {:ok, _} =
        MealBlueprints.update_plan_meal(meal, %{
          recipe_id: recipe.id,
          ingredients: [
            %{ingredient_id: rice.id, quantity: 80.0, measurement_unit_id: mu.id},
            %{ingredient_id: yogurt.id, quantity: 150.0, measurement_unit_id: mu.id}
          ]
        })

      reloaded = MealBlueprints.get_plan_meal!(user.id, meal.id)
      assert reloaded.recipe_id == recipe.id
      names = reloaded.ingredients |> Enum.map(& &1.ingredient.name) |> Enum.sort()
      assert names == ["Brown rice", "Yogurt"]
    end

    test "get_plan_meal!/2 is owner-scoped" do
      user = user_fixture()
      stranger = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)
      {:ok, _} = MealBlueprints.store_plan_meals(plan, [recipe_entry(recipe)])
      [meal] = MealBlueprints.list_plan_meals(plan.id)

      assert MealBlueprints.get_plan_meal!(user.id, meal.id).id == meal.id

      assert_raise Ecto.NoResultsError, fn ->
        MealBlueprints.get_plan_meal!(stranger.id, meal.id)
      end
    end

    test "delete_plan_meal/1 removes the slot" do
      user = user_fixture()
      {:ok, bp} = create_default(user)
      {:ok, plan} = MealBlueprints.create_plan(plan_attrs(user, bp))
      recipe = recipe_fixture(user)
      {:ok, _} = MealBlueprints.store_plan_meals(plan, [recipe_entry(recipe)])
      [meal] = MealBlueprints.list_plan_meals(plan.id)

      {:ok, _} = MealBlueprints.delete_plan_meal(meal)
      assert MealBlueprints.list_plan_meals(plan.id) == []
    end
  end
end
