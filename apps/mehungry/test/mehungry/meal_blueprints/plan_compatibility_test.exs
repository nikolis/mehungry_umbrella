defmodule Mehungry.MealBlueprints.PlanCompatibilityTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Food.{Compounds, FoundementalFoods, SpeciesCompounds}
  alias Mehungry.Food.{Ingredient, IngredientNutrient, MeasurementUnit, Nutrient}
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

  # A recipe carrying an explicit nutrient tree (incl. Energy) over `servings`.
  defp recipe_with_nutrients(user, ingredient, nutrients, servings) do
    mu = measurement_unit_fixture()

    recipe =
      recipe_fixture(user, %{
        servings: servings,
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}
        ]
      })

    {:ok, recipe} =
      recipe |> Ecto.Changeset.change(nutrients: nutrients) |> Repo.update()

    recipe
  end

  # 500 kcal + 25 g protein over 2 servings → per meal: 250 kcal, 50 kcal (20%)
  # from protein.
  defp protein_recipe(user, ing) do
    recipe_with_nutrients(
      user,
      ing,
      %{
        "Energy" => %{"name" => "Energy", "amount" => 500.0},
        "Protein" => %{"name" => "Protein", "amount" => 25.0}
      },
      2
    )
  end

  describe "analyze/2 — nutrient caloric %" do
    test "required nutrient matches when its caloric share meets the threshold" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = protein_recipe(user, ing)

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Protein"],
          required_nutrient_pcts: %{"Protein" => 20}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.kind == :nutrient and m.name == "Protein" and m.direction == :required
      assert m.pct == 20 and m.target == 20
      refute "Protein" in report.days[1].missing_required
    end

    test "required nutrient is unmet (and missing) below the threshold" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = protein_recipe(user, ing)

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Protein"],
          required_nutrient_pcts: %{"Protein" => 25}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: []} = report.meals[meal.id]
      assert "Protein" in report.days[1].missing_required
    end

    test "avoid nutrient is flagged only when it exceeds the ceiling" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = protein_recipe(user, ing)

      # Protein is 20% of calories; a 15% ceiling is exceeded → flagged.
      over =
        blueprint_with(user, %{
          avoid_nutrients: ["Protein"],
          avoid_nutrient_pcts: %{"Protein" => 15}
        })

      meals = plan_meals(user, over, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(over, meals)
      [meal] = meals

      assert %{violations: [v]} = report.meals[meal.id]
      assert v.kind == :nutrient and v.name == "Protein" and v.direction == :avoid
      assert v.pct == 20 and v.target == 15
    end

    test "avoid nutrient at exactly the ceiling is within limit (not flagged)" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = protein_recipe(user, ing)

      # Protein is exactly 20%; a 20% ceiling is not exceeded → allowed.
      bp =
        blueprint_with(user, %{
          avoid_nutrients: ["Protein"],
          avoid_nutrient_pcts: %{"Protein" => 20}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{violations: []} = report.meals[meal.id]
    end

    test "non-caloric micronutrient computes 0% (required unmet, avoid never flags)" do
      user = user_fixture()
      ing = ingredient_fixture()

      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Vitamin C" => %{"name" => "Vitamin C", "amount" => 90.0}
          },
          2
        )

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Vitamin C"],
          required_nutrient_pcts: %{"Vitamin C" => 5},
          avoid_nutrients: ["Vitamin C"],
          avoid_nutrient_pcts: %{"Vitamin C" => 5}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [], violations: []} = report.meals[meal.id]
      assert "Vitamin C" in report.days[1].missing_required
    end

    test "treats fatty-acid classes (Omega-3) as energy-bearing (9 kcal/g)" do
      user = user_fixture()
      ing = ingredient_fixture()

      # 500 kcal + 2.5 g Omega-3 over 2 servings → per meal 250 kcal, 1.25 g
      # Omega-3 = 11.25 kcal ≈ 4.5% (not 0%).
      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Omega-3" => %{"name" => "Omega-3", "amount" => 2.5}
          },
          2
        )

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Omega-3"],
          required_nutrient_pcts: %{"Omega-3" => 3}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.name == "Omega-3" and m.pct >= 4
      assert PlanCompatibility.nutrient_kcal_factor("Omega-3") == 9
    end

    test "resolves Omega-3 from raw USDA fatty-acid leaves nested under Total Fat" do
      user = user_fixture()
      ing = ingredient_fixture()

      # The real stored shape: no "Omega-3" node — just the individual n-3 acids
      # by raw USDA notation, nested two levels deep under Total Fat →
      # Polyunsaturated Fat. 500 kcal + (1.0 + 1.0 + 0.5) g n-3 over 2 servings →
      # per meal 250 kcal, 1.25 g Omega-3 = 11.25 kcal ≈ 4.5%.
      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Total Fat" => %{
              "name" => "Total Fat",
              "amount" => 20.0,
              "children" => [
                %{
                  "name" => "Polyunsaturated Fat",
                  "amount" => 10.0,
                  "children" => [
                    %{"name" => "PUFA 20:5 n-3 (EPA)", "amount" => 1.0},
                    %{"name" => "PUFA 22:6 n-3 (DHA)", "amount" => 1.0},
                    %{"name" => "PUFA 18:3 n-3 c,c,c", "amount" => 0.5}
                  ]
                }
              ]
            }
          },
          2
        )

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Omega-3"],
          required_nutrient_pcts: %{"Omega-3" => 3}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.name == "Omega-3" and m.pct >= 4
      refute "Omega-3" in report.days[1].missing_required
    end

    test "resolves a mineral target from its raw USDA 'Iron, Fe' leaf" do
      user = user_fixture()
      ing = ingredient_fixture()

      # 18 mg iron over 1 serving, nested under a Minerals parent whose own amount
      # (the children sum) must NOT be double-counted against the Iron target.
      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Minerals" => %{
              "name" => "Minerals",
              "amount" => 18.0,
              "children" => [%{"name" => "Iron, Fe", "amount" => 18.0}]
            }
          },
          1
        )

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Iron"],
          required_nutrient_pcts: %{"Iron" => 10},
          required_nutrient_modes: %{"Iron" => "amount"}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.mode == :amount and m.name == "Iron" and m.amount == 18
    end

    test "falls back to the blueprint default threshold when no pct is stored" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = protein_recipe(user, ing)

      # No pct map → default (10%); protein is 20% → met.
      bp = blueprint_with(user, %{required_nutrients: ["Protein"]})

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.target == Mehungry.MealBlueprints.Blueprint.default_nutrient_pct("Protein")
    end

    test "the per-nutrient default makes a trace-fat goal (Omega-3) reachable" do
      alias Mehungry.MealBlueprints.Blueprint

      # The flat macro default is unreachable for a trace fat; the name-aware
      # default is a realistic sub-1% caloric share.
      assert Blueprint.default_nutrient_pct("Omega-3") < Blueprint.default_nutrient_pct()
      assert Blueprint.default_nutrient_pct("Protein") == Blueprint.default_nutrient_pct()

      user = user_fixture()
      ing = ingredient_fixture()

      # 500 kcal + 2.5 g Omega-3 over 2 servings → ≈4.5% caloric share.
      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Omega-3" => %{"name" => "Omega-3", "amount" => 2.5}
          },
          2
        )

      # No explicit pct → falls back to the Omega-3 default, which this intake clears.
      bp = blueprint_with(user, %{required_nutrients: ["Omega-3"]})

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.name == "Omega-3"
      assert m.target == Blueprint.default_nutrient_pct("Omega-3")
      refute "Omega-3" in report.days[1].missing_required
    end

    test "a dietary-fiber goal defaults to amount mode (grams/day), not caloric %" do
      alias Mehungry.MealBlueprints.Blueprint

      # Fiber's caloric share is intrinsically tiny, so it defaults to a per-day
      # grams floor rather than a %. A bare "Dietary Fiber" label resolves the
      # same via the "fiber" match.
      assert Blueprint.default_nutrient_mode("Fiber") == "amount"
      assert Blueprint.default_nutrient_mode("Dietary Fiber") == "amount"
      assert Blueprint.default_nutrient_amount("Fiber") == 25
      assert Blueprint.default_nutrient_mode("Protein") == "pct"

      user = user_fixture()
      ing = ingredient_fixture()

      # 500 kcal + 30 g Fiber over 1 serving → 30 g/day, clears the ≥25 g floor.
      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Fiber" => %{"name" => "Fiber", "amount" => 30.0}
          },
          1
        )

      # No explicit mode/value → falls back to amount mode at the DRI default.
      bp = blueprint_with(user, %{required_nutrients: ["Fiber"]})

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{matches: [m]} = report.meals[meal.id]
      assert m.name == "Fiber"
      assert m.mode == :amount
      assert m.target == Blueprint.default_nutrient_amount("Fiber")
      refute "Fiber" in report.days[1].missing_required
    end

    test "a low dietary-fiber day leaves the amount-mode goal unmet" do
      user = user_fixture()
      ing = ingredient_fixture()

      # 500 kcal + 2.2 g Fiber over 1 serving → 2.2 g/day, far below ≥25 g.
      recipe =
        recipe_with_nutrients(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Fiber" => %{"name" => "Fiber", "amount" => 2.2}
          },
          1
        )

      bp = blueprint_with(user, %{required_nutrients: ["Fiber"]})

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)

      assert "Fiber" in report.days[1].missing_required
    end
  end

  describe "analyze/2 — nutrient amount mode" do
    # 500 kcal + 1500 mg sodium over 2 servings → per meal/day: 750 mg sodium.
    defp sodium_recipe(user, ing) do
      recipe_with_nutrients(
        user,
        ing,
        %{
          "Energy" => %{"name" => "Energy", "amount" => 500.0},
          "Sodium" => %{"name" => "Sodium", "amount" => 1500.0}
        },
        2
      )
    end

    test "avoid amount flags a nutrient whose per-day total exceeds the cap" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = sodium_recipe(user, ing)

      bp =
        blueprint_with(user, %{
          avoid_nutrients: ["Sodium"],
          avoid_nutrient_pcts: %{"Sodium" => 500},
          avoid_nutrient_modes: %{"Sodium" => "amount"}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{violations: [v]} = report.meals[meal.id]
      assert v.mode == :amount and v.name == "Sodium" and v.amount == 750 and v.target == 500
    end

    test "avoid amount stays within a generous cap (not flagged)" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = sodium_recipe(user, ing)

      bp =
        blueprint_with(user, %{
          avoid_nutrients: ["Sodium"],
          avoid_nutrient_pcts: %{"Sodium" => 2300},
          avoid_nutrient_modes: %{"Sodium" => "amount"}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      assert %{violations: []} = report.meals[meal.id]
    end

    test "required amount is met only when the per-day total reaches the floor" do
      user = user_fixture()
      ing = ingredient_fixture()
      recipe = sodium_recipe(user, ing)

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Sodium"],
          required_nutrient_pcts: %{"Sodium" => 700},
          required_nutrient_modes: %{"Sodium" => "amount"}
        })

      meals = plan_meals(user, bp, [%{day_index: 1, meal_type: "breakfast", recipe: recipe}])
      report = PlanCompatibility.analyze(bp, meals)
      [meal] = meals

      # 750 mg ≥ 700 mg floor → match, and not missing.
      assert %{matches: [m]} = report.meals[meal.id]
      assert m.mode == :amount and m.amount == 750 and m.target == 700
      refute "Sodium" in report.days[1].missing_required
    end
  end

  describe "analyze/2 — whole-food ingredient meals" do
    test "a logged ingredient contributes nutrients toward a goal, like a recipe would" do
      user = user_fixture()
      # measurement_unit_fixture defaults to "gram", which gram_unit_ids/0 matches,
      # so a logged quantity passes straight through as grams.
      gram = measurement_unit_fixture()

      ingredient = %Ingredient{
        id: System.unique_integer([:positive]),
        ingredient_portions: [],
        ingredient_nutrients: [
          %IngredientNutrient{
            amount: 18.0,
            nutrient_id: System.unique_integer([:positive]),
            nutrient: %Nutrient{
              name: "Iron, Fe",
              number: "303",
              measurement_unit: %MeasurementUnit{name: "mg"}
            }
          }
        ]
      }

      # A whole-food ingredient meal (recipe_id nil, ingredients populated) — the
      # shape `MealBlueprints.user_meals_to_plan_meals/2` produces for the calendar.
      meal = %{
        id: 1,
        day_index: 1,
        meal_type: "breakfast",
        recipe_id: nil,
        recipe: nil,
        ingredients: [
          %{
            ingredient_id: ingredient.id,
            ingredient: ingredient,
            quantity: 100.0,
            measurement_unit_id: gram.id,
            ingredient_portion_id: nil
          }
        ]
      }

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Iron"],
          required_nutrient_pcts: %{"Iron" => 10},
          required_nutrient_modes: %{"Iron" => "amount"}
        })

      report = PlanCompatibility.analyze(bp, [meal])

      assert %{matches: [m]} = report.meals[1]
      assert m.mode == :amount and m.name == "Iron" and m.amount == 18
      refute "Iron" in report.days[1].missing_required
    end
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
