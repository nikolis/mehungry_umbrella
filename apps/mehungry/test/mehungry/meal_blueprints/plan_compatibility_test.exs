defmodule Mehungry.MealBlueprints.PlanCompatibilityTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Food.{Compounds, FoundementalFoods, SpeciesCompounds}
  alias Mehungry.MealBlueprints
  alias Mehungry.MealBlueprints.PlanCompatibility
  alias Mehungry.Repo

  # A recipe whose single ingredient is `ingredient`, with `energy` kcal stored on
  # the recipe over `servings` servings (so per-serving = energy/servings).
  defp recipe_with(user, ingredient, energy, servings) do
    mu = measurement_unit_fixture()

    recipe =
      recipe_fixture(user, %{
        servings: servings,
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}
        ]
      })

    {:ok, recipe} =
      recipe
      |> Ecto.Changeset.change(
        nutrients: %{"Energy" => %{"name" => "Energy", "amount" => energy}}
      )
      |> Repo.update()

    recipe
  end

  # Links `ingredient` to a fresh species that "contains" a compound of the given
  # name/type (the canonical species fact path).
  defp species_compound(ingredient, name, type) do
    {:ok, species} =
      FoundementalFoods.create_species(%{name: "species-#{System.unique_integer()}"})

    {:ok, _} =
      FoundementalFoods.create_foundemental_food(%{
        foundemental_species_id: species.id,
        usda_name: "usda-#{System.unique_integer()}",
        ingredient_id: ingredient.id
      })

    {:ok, compound} = Compounds.create_compound(%{name: name, compound_type: type})

    {:ok, _} =
      SpeciesCompounds.upsert_species_relationship(%{
        foundemental_species_id: species.id,
        compound_id: compound.id,
        relationship_type: "contains",
        source: "manual"
      })

    compound
  end

  # Links `ingredient` directly to a compound (the ingredient-level fact path).
  defp ingredient_compound(ingredient, name, type) do
    {:ok, compound} = Compounds.create_compound(%{name: name, compound_type: type})

    {:ok, _} =
      Compounds.upsert_compound_relationship(%{
        ingredient_id: ingredient.id,
        compound_id: compound.id,
        relationship_type: "contains",
        source: "manual"
      })

    compound
  end

  defp blueprint_with(user, overrides) do
    attrs =
      user.id
      |> MealBlueprints.default_blueprint_attrs("Test blueprint")
      |> Map.merge(overrides)

    {:ok, bp} = MealBlueprints.create_blueprint(attrs)
    MealBlueprints.get_blueprint!(user.id, bp.id)
  end

  # Builds a completed plan holding `entries` (day_index/meal_type/recipe) and
  # returns the deep-loaded plan meals the analyzer consumes.
  defp plan_meals(user, blueprint, entries) do
    {:ok, plan} =
      MealBlueprints.create_plan(%{
        name: "Plan",
        start_date: Date.utc_today(),
        status: "generating",
        blueprint_id: blueprint.id,
        user_id: user.id
      })

    normalized =
      Enum.map(entries, fn e ->
        %{
          day_index: e.day_index,
          meal_type: e.meal_type,
          recipe_id: e.recipe.id,
          cooking_portions: 2,
          ingredient_id: nil,
          quantity: nil,
          measurement_unit_id: nil,
          ingredient_portion_id: nil
        }
      end)

    {:ok, _} = MealBlueprints.store_plan_meals(plan, normalized)
    MealBlueprints.list_plan_meals_with_ingredients(plan.id)
  end

  describe "analyze/2 — compound signals" do
    test "flags an avoided compound as a per-meal violation (species path)" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Oxalate", "oxalate")
      recipe = recipe_with(user, ing, 500.0, 2)

      bp = blueprint_with(user, %{avoid_compounds: ["Oxalate"]})
      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])

      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{violations: [v], matches: []} = report.meals[meal.id]
      assert v.kind == :compound and v.direction == :avoid and v.name == "Oxalate"
      assert report.days[1].violation_count == 1
    end

    test "flags a required compound as a per-meal match (ingredient path)" do
      user = user_fixture()
      ing = ingredient_fixture()
      ingredient_compound(ing, "Flavonoid", "polyphenol")
      recipe = recipe_with(user, ing, 500.0, 2)

      bp = blueprint_with(user, %{required_compounds: ["Flavonoid"]})
      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])

      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{violations: [], matches: [m]} = report.meals[meal.id]
      assert m.direction == :required and m.name == "Flavonoid" and m.via == :direct
    end

    test "matches a compound family label and collapses to one badge" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Quercetin", "polyphenol")
      ingredient_compound(ing, "Catechin", "polyphenol")
      recipe = recipe_with(user, ing, 500.0, 2)

      # "Polyphenols" is a family label, not a specific compound name.
      bp = blueprint_with(user, %{avoid_compounds: ["Polyphenols"]})
      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])

      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{violations: [v]} = report.meals[meal.id]
      assert v.via == :family and v.name == "Polyphenols"
    end
  end

  describe "analyze/2 — daily energy" do
    test "reports :over when the day's meals exceed the calorie target" do
      user = user_fixture()
      ing = ingredient_fixture()
      # per-serving 900 kcal → one meal contributes 900.
      recipe = recipe_with(user, ing, 1800.0, 2)

      bp =
        blueprint_with(user, %{
          days:
            for i <- 1..7 do
              %{
                day_index: i,
                total_calorie_target: if(i == 1, do: 700, else: nil),
                meals: for(mt <- Mehungry.History.MealType.values(), do: %{meal_type: mt})
              }
            end
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)

      assert report.days[1].calorie_status == :over
      assert report.days[1].calorie_total == 900
      assert report.days[1].calorie_delta == 200
    end

    test "reports :no_target for a day without a calorie aim" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = recipe_with(user, ing, 400.0, 2)

      bp = blueprint_with(user, %{})
      meals = plan_meals(user, bp, [%{day_index: 2, meal_type: "lunch", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)

      assert report.days[2].calorie_status == :no_target
    end
  end

  describe "analyze/2 — missing required" do
    test "lists a required compound no meal that day includes" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Oxalate", "oxalate")
      recipe = recipe_with(user, ing, 400.0, 2)

      bp = blueprint_with(user, %{required_compounds: ["Lycopene"]})
      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)

      assert "Lycopene" in report.days[1].missing_required
    end
  end
end
