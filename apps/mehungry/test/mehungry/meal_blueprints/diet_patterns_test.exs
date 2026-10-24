defmodule Mehungry.MealBlueprints.DietPatternsTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures

  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.DietPatterns
  alias Mehungry.History.MealType

  @expected_keys [
    :mediterranean,
    :low_fodmap,
    :ketogenic,
    :low_carb,
    :high_protein,
    :low_fat,
    :zone,
    :atkins,
    :dash,
    :mind,
    :nordic,
    :whole_food_plant_based,
    :vegan,
    :vegetarian,
    :pescatarian,
    :paleo,
    :whole30,
    :gluten_free,
    :dairy_free,
    :low_sodium,
    :low_glycemic
  ]

  @expected_names [
    "Mediterranean Diet",
    "Low-FODMAP Diet",
    "Ketogenic Diet",
    "Low-Carb Diet",
    "High-Protein Diet",
    "Low-Fat Diet",
    "Zone Diet",
    "Atkins Diet",
    "DASH Diet",
    "MIND Diet",
    "Nordic Diet",
    "Whole-Food Plant-Based Diet",
    "Vegan Diet",
    "Vegetarian Diet",
    "Pescatarian Diet",
    "Paleo Diet",
    "Whole30 Diet",
    "Gluten-Free Diet",
    "Dairy-Free Diet",
    "Low-Sodium Diet",
    "Low-Glycemic Diet"
  ]

  test "exposes every diet-pattern descriptor with unique names" do
    patterns = DietPatterns.all()
    assert length(patterns) == 21
    assert DietPatterns.keys() == @expected_keys

    names = Enum.map(patterns, & &1.name)
    assert names == @expected_names
    assert length(Enum.uniq(names)) == 21
  end

  test "each pattern builds a valid, insertable blueprint with the expected shape" do
    user = user_fixture()

    for key <- DietPatterns.keys() do
      case DietPatterns.create_for_user(user.id, key) do
        {:ok, bp} ->
          bp = MealBlueprints.get_blueprint!(user.id, bp.id)

          # 7 days × 5 canonical slots.
          assert length(bp.days) == 7

          for day <- bp.days do
            slots = Enum.map(day.meals, & &1.meal_type)
            assert Enum.sort(slots) == Enum.sort(MealType.values())

            for meal <- day.meals do
              assert meal.protein_pct + meal.carbs_pct + meal.fats_pct == 100
            end
          end

          MealBlueprints.delete_blueprint(bp)

        {:error, changeset} ->
          flunk("pattern #{key} invalid: #{inspect(errors_on(changeset))}")
      end
    end
  end

  test "Mediterranean is an encourage pattern (nutrients/compounds, no avoid foods)" do
    med = DietPatterns.get(:mediterranean)

    assert "Omega-3" in med.required_nutrients
    assert "Polyphenols" in med.required_compounds
    assert "Saturated Fat" in med.avoid_nutrients
    assert "olive oil" in med.preferred_foods
    assert med.avoid_foods == []
  end

  test "Low-FODMAP is an avoidance pattern driven by avoid_foods + FODMAP compound" do
    fodmap = DietPatterns.get(:low_fodmap)

    assert "FODMAP" in fodmap.avoid_compounds
    assert "onion" in fodmap.avoid_foods
    assert "garlic" in fodmap.avoid_foods
    assert "wheat" in fodmap.avoid_foods
    assert "rice" in fodmap.preferred_foods
  end

  test "Ketogenic is a very-low-carb, high-fat macro pattern" do
    keto = DietPatterns.get(:ketogenic)
    macro = keto.days |> hd() |> Map.get(:meals) |> hd()

    assert {macro.protein_pct, macro.carbs_pct, macro.fats_pct} == {20, 5, 75}
    assert "bread" in keto.avoid_foods
    assert "sugar" in keto.avoid_foods
  end

  test "Vegan is an avoidance pattern excluding all animal products" do
    vegan = DietPatterns.get(:vegan)

    assert "meat" in vegan.avoid_foods
    assert "dairy" in vegan.avoid_foods
    assert "eggs" in vegan.avoid_foods
    assert "honey" in vegan.avoid_foods
    assert "legumes" in vegan.preferred_foods
  end

  test "DASH is an encourage pattern using only resolving nutrient tags" do
    dash = DietPatterns.get(:dash)

    assert "Fiber" in dash.required_nutrients
    assert "Sodium" in dash.avoid_nutrients
    assert "Saturated Fat" in dash.avoid_nutrients
  end

  test "attrs_for carries avoid_foods through to the created blueprint" do
    user = user_fixture()
    {:ok, bp} = DietPatterns.create_for_user(user.id, :low_fodmap)

    assert "onion" in bp.avoid_foods
    assert "garlic" in bp.avoid_foods
  end

  test "creates a self-contained blueprint with no backing condition" do
    user = user_fixture()
    {:ok, bp} = DietPatterns.create_for_user(user.id, :mediterranean)
    assert is_nil(bp.condition_id)
  end

  describe "create_missing_for_user/1" do
    test "creates all patterns the first time, none the second (idempotent by name)" do
      user = user_fixture()

      assert {:ok, 21} = DietPatterns.create_missing_for_user(user.id)
      assert {:ok, 0} = DietPatterns.create_missing_for_user(user.id)

      names =
        user.id |> MealBlueprints.list_blueprints_for_user() |> Enum.map(& &1.name) |> Enum.sort()

      assert names == Enum.sort(@expected_names)
    end
  end

  describe "seed signature" do
    test "a freshly-seeded blueprint reloads to the same signature it was stamped with" do
      user = user_fixture()
      {:ok, bp} = DietPatterns.create_for_user(user.id, :mediterranean)

      assert bp.seeded_pattern_key == "mediterranean"
      assert is_binary(bp.seed_signature)

      reloaded = MealBlueprints.get_blueprint!(user.id, bp.id)

      # The invariant the whole sync rests on: the attrs-side signature stamped at
      # seed time equals the blueprint-side signature computed after reload.
      assert DietPatterns.content_signature_from_blueprint(reloaded) == bp.seed_signature
    end
  end

  describe "sync_for_user/1" do
    test "creates all patterns the first time" do
      user = user_fixture()
      assert {:ok, %{created: 21, refreshed: 0, skipped: 0, adopted: 0}} =
               DietPatterns.sync_for_user(user.id)
    end

    test "a second sync with no template change is a no-op (all skipped, no duplicates)" do
      user = user_fixture()
      {:ok, _} = DietPatterns.sync_for_user(user.id)

      assert {:ok, %{created: 0, refreshed: 0, skipped: 21, adopted: 0}} =
               DietPatterns.sync_for_user(user.id)

      assert length(MealBlueprints.list_blueprints_for_user(user.id)) == 21
    end

    test "refreshes an unedited copy whose template has changed since seeding" do
      user = user_fixture()
      {:ok, bp} = DietPatterns.create_for_user(user.id, :mediterranean)

      # Simulate "template changed since this was seeded": rewrite the copy's
      # description to a stale value and re-stamp its seed_signature to match that
      # stale content — so it reads as *unedited relative to its (stale) seed*,
      # while the live template now differs.
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      {:ok, stale} = MealBlueprints.update_blueprint(loaded, %{description: "STALE"})
      stale = MealBlueprints.get_blueprint!(user.id, stale.id)
      {:ok, _} =
        MealBlueprints.set_blueprint_provenance(
          stale,
          "mediterranean",
          DietPatterns.content_signature_from_blueprint(stale)
        )

      assert {:ok, %{refreshed: refreshed}} = DietPatterns.sync_for_user(user.id)
      assert refreshed >= 1

      refreshed_bp = MealBlueprints.get_blueprint!(user.id, bp.id)
      assert refreshed_bp.description == DietPatterns.get(:mediterranean).description
    end

    test "leaves a user-edited copy untouched" do
      user = user_fixture()
      {:ok, bp} = DietPatterns.create_for_user(user.id, :mediterranean)

      # Edit the copy WITHOUT re-stamping the signature → current content now
      # diverges from seed_signature, marking it user-edited.
      loaded = MealBlueprints.get_blueprint!(user.id, bp.id)
      {:ok, _} = MealBlueprints.update_blueprint(loaded, %{description: "my notes"})

      {:ok, tally} = DietPatterns.sync_for_user(user.id)
      assert tally.refreshed == 0

      kept = MealBlueprints.get_blueprint!(user.id, bp.id)
      assert kept.description == "my notes"
    end

    test "adopts a legacy name-matched copy (no provenance) without creating a duplicate" do
      user = user_fixture()

      # A blueprint created the old way: pattern content + name, but no provenance.
      {:ok, legacy} =
        DietPatterns.attrs_for(:vegan, user.id) |> MealBlueprints.create_blueprint()

      assert is_nil(legacy.seeded_pattern_key)

      {:ok, tally} = DietPatterns.sync_for_user(user.id)

      # The one existing Vegan is adopted (not duplicated); the other 20 created.
      assert tally.adopted == 1
      assert tally.created == 20

      vegans =
        user.id
        |> MealBlueprints.list_blueprints_for_user()
        |> Enum.filter(&(&1.name == "Vegan Diet"))

      assert length(vegans) == 1
      assert hd(vegans).seeded_pattern_key == "vegan"
      # Adopted with a nil signature → never auto-refreshed.
      assert is_nil(hd(vegans).seed_signature)
    end
  end
end
