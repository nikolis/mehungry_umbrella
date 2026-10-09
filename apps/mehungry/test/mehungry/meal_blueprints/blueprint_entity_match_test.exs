defmodule Mehungry.MealBlueprints.BlueprintEntityMatchTest do
  @moduledoc """
  Covers `PlanCompatibility.match_recipes/2` and `match_ingredients/2` — the
  single-entity blueprint matching the REST layer exposes as `blueprint_match`.
  """
  use Mehungry.DataCase, async: false

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Food.{Compounds, FoundementalFoods, SpeciesCompounds}
  alias Mehungry.Food.{IngredientNutrient, Nutrient}
  alias Mehungry.MealBlueprints
  alias Mehungry.Repo

  setup do
    # NutrientTargets caches label→nutrient-ids globally; clear it so a label a
    # previous test cached (against a different nutrient registry) can't leak in.
    Cachex.clear(:health_cache)
    :ok
  end

  defp blueprint_with(user, overrides) do
    attrs =
      user.id
      |> MealBlueprints.default_blueprint_attrs("Test blueprint")
      |> Map.merge(overrides)

    {:ok, bp} = MealBlueprints.create_blueprint(attrs)
    MealBlueprints.get_blueprint!(user.id, bp.id)
  end

  defp recipe_with(user, ingredient, nutrients, servings) do
    mu = measurement_unit_fixture()

    recipe =
      recipe_fixture(user, %{
        servings: servings,
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}
        ]
      })

    {:ok, recipe} = recipe |> Ecto.Changeset.change(nutrients: nutrients) |> Repo.update()
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

  describe "match_recipes/2" do
    test "required compound surfaces as a match, avoided compound as a violation" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Oxalate", "oxalate")
      recipe = recipe_with(user, ing, %{"Energy" => %{"name" => "Energy", "amount" => 300.0}}, 1)

      req = blueprint_with(user, %{required_compounds: ["Oxalate"]})
      assert %{matches: [m], violations: []} = MealBlueprints.match_recipes(req, [recipe])[recipe.id]
      assert m.kind == :compound and m.name == "Oxalate" and m.direction == :required

      avoid = blueprint_with(user, %{avoid_compounds: ["Oxalate"]})
      report = MealBlueprints.match_recipes(avoid, [recipe])[recipe.id]
      assert [v] = report.violations
      assert v.kind == :compound and v.name == "Oxalate" and v.direction == :avoid
    end

    test "required nutrient matches on its per-serving caloric share" do
      user = user_fixture()
      ing = ingredient_fixture()

      # 500 kcal + 25 g protein over 2 servings → per serving 250 kcal, 50 kcal
      # (20%) from protein.
      recipe =
        recipe_with(
          user,
          ing,
          %{
            "Energy" => %{"name" => "Energy", "amount" => 500.0},
            "Protein" => %{"name" => "Protein", "amount" => 25.0}
          },
          2
        )

      bp =
        blueprint_with(user, %{
          required_nutrients: ["Protein"],
          required_nutrient_pcts: %{"Protein" => 20}
        })

      %{} = reports = MealBlueprints.match_recipes(bp, [recipe])
      assert %{matches: [m], violations: []} = reports[recipe.id]
      assert m.kind == :nutrient and m.name == "Protein" and m.mode == :pct
      assert m.pct == 20 and m.target == 20
    end

    test "returns an empty map for no recipes" do
      user = user_fixture()
      bp = blueprint_with(user, %{required_compounds: ["Oxalate"]})
      assert MealBlueprints.match_recipes(bp, []) == %{}
    end
  end

  describe "match_ingredients/2" do
    test "required compound surfaces as a match (species path)" do
      user = user_fixture()
      ing = ingredient_fixture()
      species_compound(ing, "Flavonoid", "polyphenol")

      bp = blueprint_with(user, %{required_compounds: ["Flavonoid"]})
      reports = MealBlueprints.match_ingredients(bp, [ing])

      assert %{matches: [m], violations: []} = reports[ing.id]
      assert m.kind == :compound and m.name == "Flavonoid" and m.direction == :required
    end

    test "avoided nutrient surfaces as a per-100g violation" do
      user = user_fixture()
      ing = ingredient_fixture()

      {:ok, nutrient} =
        %Nutrient{} |> Nutrient.changeset(%{name: "Sodium, Na", rank: 5800}) |> Repo.insert()

      # 480 mg/100g ≥ the 400 mg/100g "high in sodium" threshold → a violation.
      Repo.insert!(%IngredientNutrient{
        ingredient_id: ing.id,
        nutrient_id: nutrient.id,
        amount: 480.0
      })

      bp = blueprint_with(user, %{avoid_nutrients: ["Sodium"]})
      reports = MealBlueprints.match_ingredients(bp, [ing])

      assert %{violations: [v]} = reports[ing.id]
      assert v.kind == :nutrient and v.name == "Sodium" and v.direction == :avoid
      assert v.mode == :per_100g and v.per_100g == 480.0 and v.threshold == 400.0
    end

    test "returns an empty map for no ingredients" do
      user = user_fixture()
      bp = blueprint_with(user, %{avoid_nutrients: ["Sodium"]})
      assert MealBlueprints.match_ingredients(bp, []) == %{}
    end
  end
end
