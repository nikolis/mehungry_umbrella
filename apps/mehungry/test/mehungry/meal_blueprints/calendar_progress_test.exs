defmodule Mehungry.MealBlueprints.CalendarProgressTest do
  use Mehungry.DataCase, async: true

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Food.{Compounds, FoundementalFoods, SpeciesCompounds}
  alias Mehungry.History
  alias Mehungry.History.MealType
  alias Mehungry.MealBlueprints
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

  # A blueprint with the given overrides; day 1 gets `day1_target` kcal.
  defp blueprint_with(user, overrides, day1_target \\ nil) do
    days =
      for i <- 1..7 do
        %{
          day_index: i,
          total_calorie_target: if(i == 1, do: day1_target, else: nil),
          meals: for(mt <- MealType.values(), do: %{meal_type: mt})
        }
      end

    attrs =
      user.id
      |> MealBlueprints.default_blueprint_attrs("Test blueprint")
      |> Map.merge(overrides)
      |> Map.put(:days, days)

    {:ok, bp} = MealBlueprints.create_blueprint(attrs)
    MealBlueprints.get_blueprint!(user.id, bp.id)
  end

  # Logs `recipe` on the user's calendar on `date` as a `meal_type` meal.
  defp log_recipe_meal(user, recipe, date, meal_type) do
    {:ok, meal} =
      History.create_user_meal(%{
        title: MealType.label(meal_type),
        meal_type: meal_type,
        start_dt: NaiveDateTime.new!(date, ~T[08:00:00]),
        user_id: user.id,
        recipe_user_meals: [
          %{recipe_id: recipe.id, cooking_portions: 2, consume_portions: 1, cooking: true}
        ]
      })

    meal
  end

  describe "calendar_progress/3" do
    test "reports required coverage, avoid violations, and calorie status for the week" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Flavonoid", "polyphenol")
      ingredient_compound(ing, "Oxalate", "oxalate")
      # per-serving 700 kcal (servings 1), matching the day-1 target exactly.
      recipe = recipe_with(user, ing, 700.0, 1)

      bp =
        blueprint_with(
          user,
          %{required_compounds: ["Flavonoid"], avoid_compounds: ["Oxalate"]},
          700
        )

      week_start = Date.beginning_of_week(Date.utc_today())
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      assert progress.week_start == week_start
      assert [%{name: "Flavonoid", met: true}] = progress.required
      assert [%{name: "Oxalate", direction: :avoid}] = progress.violations
      assert progress.days[1].calorie_status == :ok
      assert progress.calorie_days_on_target == 1
      assert progress.calorie_days_with_target == 1
    end

    test "marks a required goal unmet when no meal that week covers it" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Flavonoid", "polyphenol")
      recipe = recipe_with(user, ing, 400.0, 2)

      bp = blueprint_with(user, %{required_compounds: ["Lycopene"]})

      week_start = Date.beginning_of_week(Date.utc_today())
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      assert [%{name: "Lycopene", met: false}] = progress.required
      assert progress.violations == []
    end

    test "reports required/avoid nutrient coverage by caloric % across the week" do
      user = user_fixture()
      ing = ingredient_fixture()
      mu = measurement_unit_fixture()

      # 700 kcal + 40 g protein over 1 serving → protein = 160 kcal = ~23%.
      recipe =
        recipe_fixture(user, %{
          servings: 1,
          recipe_ingredients: [%{ingredient_id: ing.id, measurement_unit_id: mu.id, quantity: 5}]
        })

      {:ok, recipe} =
        recipe
        |> Ecto.Changeset.change(
          nutrients: %{
            "Energy" => %{"name" => "Energy", "amount" => 700.0},
            "Protein" => %{"name" => "Protein", "amount" => 40.0}
          }
        )
        |> Repo.update()

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Protein"],
          required_nutrient_pcts: %{"Protein" => 20},
          avoid_nutrients: ["Protein"],
          avoid_nutrient_pcts: %{"Protein" => 30}
        })

      week_start = Date.beginning_of_week(Date.utc_today())
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      assert [%{name: "Protein", met: true, target: 20, pct: pct, amount: amount}] =
               progress.required

      assert pct >= 22 and pct <= 24
      # pct-mode entries also carry the current absolute quantity (40 g protein).
      assert amount == 40
      # 23% is below the 30% avoid ceiling → listed but not flagged.
      assert [%{name: "Protein", flagged: false, target: 30}] = progress.avoid
      assert progress.violations == []
    end

    test "evaluates an amount-mode avoid cap per day in the nutrient's unit" do
      user = user_fixture()
      ing = ingredient_fixture()
      mu = measurement_unit_fixture()

      # 700 kcal + 1800 mg sodium over 1 serving → 1800 mg/day.
      recipe =
        recipe_fixture(user, %{
          servings: 1,
          recipe_ingredients: [%{ingredient_id: ing.id, measurement_unit_id: mu.id, quantity: 5}]
        })

      {:ok, recipe} =
        recipe
        |> Ecto.Changeset.change(
          nutrients: %{
            "Energy" => %{"name" => "Energy", "amount" => 700.0},
            "Sodium" => %{"name" => "Sodium", "amount" => 1800.0}
          }
        )
        |> Repo.update()

      bp =
        blueprint_with(user, %{
          avoid_nutrients: ["Sodium"],
          avoid_nutrient_pcts: %{"Sodium" => 1500},
          avoid_nutrient_modes: %{"Sodium" => "amount"}
        })

      week_start = Date.beginning_of_week(Date.utc_today())
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      # 1800 mg/day exceeds the 1500 mg cap → flagged, max day total reported.
      assert [%{name: "Sodium", mode: :amount, amount: 1800, target: 1500, flagged: true}] =
               progress.avoid
    end

    test "amount-mode entries also carry the complementary caloric %" do
      user = user_fixture()
      ing = ingredient_fixture()
      mu = measurement_unit_fixture()

      # 400 kcal + 20 g fiber over 1 serving → 20 g/day; fiber ≈ 2 kcal/g → 40 kcal
      # = 10% of calories.
      recipe =
        recipe_fixture(user, %{
          servings: 1,
          recipe_ingredients: [%{ingredient_id: ing.id, measurement_unit_id: mu.id, quantity: 5}]
        })

      {:ok, recipe} =
        recipe
        |> Ecto.Changeset.change(
          nutrients: %{
            "Energy" => %{"name" => "Energy", "amount" => 400.0},
            "Fiber" => %{"name" => "Fiber", "amount" => 20.0}
          }
        )
        |> Repo.update()

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Fiber"],
          required_nutrient_pcts: %{"Fiber" => 15},
          required_nutrient_modes: %{"Fiber" => "amount"}
        })

      week_start = Date.beginning_of_week(Date.utc_today())
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      assert [%{name: "Fiber", mode: :amount, amount: 20, target: 15, met: true, pct: pct}] =
               progress.required

      assert pct == 10
    end

    test "days_progress carries each day's own coverage, not the week's" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Flavonoid", "polyphenol")
      recipe = recipe_with(user, ing, 500.0, 1)

      bp = blueprint_with(user, %{required_compounds: ["Flavonoid"]})

      week_start = Date.beginning_of_week(Date.utc_today())
      # Only day 1 covers the Flavonoid goal; day 2 has no meals.
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      # Week-level rollup is met (day 1 covers it)...
      assert [%{name: "Flavonoid", met: true}] = progress.required

      # ...but each day reports its own status, not the week's.
      assert [%{name: "Flavonoid", met: true}] = progress.days_progress[1].required
      assert [%{name: "Flavonoid", met: false}] = progress.days_progress[2].required
    end

    test "days_progress measures a nutrient's caloric % per day" do
      user = user_fixture()
      ing = ingredient_fixture()
      mu = measurement_unit_fixture()

      # 700 kcal + 40 g protein over 1 serving → ~23% on the day it's logged.
      recipe =
        recipe_fixture(user, %{
          servings: 1,
          recipe_ingredients: [%{ingredient_id: ing.id, measurement_unit_id: mu.id, quantity: 5}]
        })

      {:ok, recipe} =
        recipe
        |> Ecto.Changeset.change(
          nutrients: %{
            "Energy" => %{"name" => "Energy", "amount" => 700.0},
            "Protein" => %{"name" => "Protein", "amount" => 40.0}
          }
        )
        |> Repo.update()

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Protein"],
          required_nutrient_pcts: %{"Protein" => 20}
        })

      week_start = Date.beginning_of_week(Date.utc_today())
      log_recipe_meal(user, recipe, week_start, "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      # Day 1 clears the 20% protein floor; day 2 (no meals) reads 0%, unmet.
      assert [%{name: "Protein", met: true, pct: d1_pct}] = progress.days_progress[1].required
      assert d1_pct >= 22 and d1_pct <= 24
      assert [%{name: "Protein", met: false, pct: 0}] = progress.days_progress[2].required
    end

    test "ignores meals outside the measured week" do
      user = user_fixture()
      ing = ingredient_fixture()
      ingredient_compound(ing, "Oxalate", "oxalate")
      recipe = recipe_with(user, ing, 400.0, 2)

      bp = blueprint_with(user, %{avoid_compounds: ["Oxalate"]})

      week_start = Date.beginning_of_week(Date.utc_today())
      # Logged a full week before the measured window.
      log_recipe_meal(user, recipe, Date.add(week_start, -7), "breakfast")

      progress = MealBlueprints.calendar_progress(user.id, bp, week_start)

      assert progress.violations == []
    end
  end
end
