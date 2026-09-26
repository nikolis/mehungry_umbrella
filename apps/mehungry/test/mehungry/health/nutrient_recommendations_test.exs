defmodule Mehungry.Health.NutrientRecommendationsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.Health.NutrientTargets

  alias Mehungry.Food.{
    FoundementalFood,
    FoundementalFoodSpecies,
    IngredientNutrient,
    Nutrient
  }

  # The NutrientTargets resolver caches nutrient-id lookups in the process-global
  # :health_cache; clear it between sandboxed tests so a prior test's rows don't leak.
  setup do
    Cachex.clear(:health_cache)
    :ok
  end

  describe "NutrientRecommendation schema + CRUD" do
    test "add_nutrient_recommendation upserts on (condition, nutrient, source)" do
      {:ok, cond} = Health.upsert_condition(%{name: "Anti-Inflammatory", category: "pattern"})

      {:ok, rec} =
        Health.add_nutrient_recommendation(cond.id, "Omega-3", %{
          recommendation: "encourage",
          severity: "moderate",
          evidence_level: "strong",
          source: "guideline",
          source_reference: %{"label" => "AHA", "url" => "https://example.com"}
        })

      assert rec.nutrient_name == "Omega-3"
      assert rec.recommendation == "encourage"

      # Re-assert from the same source → same row, updated.
      {:ok, rec2} =
        Health.add_nutrient_recommendation(cond.id, "Omega-3", %{
          recommendation: "encourage",
          severity: "high",
          source: "guideline",
          source_reference: %{"label" => "AHA", "url" => "https://example.com"}
        })

      assert rec2.id == rec.id
      assert rec2.severity == "high"
      assert [%{nutrient_name: "Omega-3"}] = Health.nutrient_recommendations_for_condition(cond.id)
    end

    test "rejects a bad direction and requires a citation for guideline source" do
      {:ok, cond} = Health.upsert_condition(%{name: "Anti-Inflammatory"})

      assert {:error, cs} =
               Health.create_nutrient_recommendation(%{
                 condition_id: cond.id,
                 nutrient_name: "Omega-3",
                 recommendation: "bogus",
                 source: "guideline",
                 source_reference: %{"label" => "x"}
               })

      assert %{recommendation: _} = errors_on(cs)

      assert {:error, cs2} =
               Health.create_nutrient_recommendation(%{
                 condition_id: cond.id,
                 nutrient_name: "Omega-3",
                 recommendation: "encourage",
                 source: "guideline"
               })

      assert %{source_reference: _} = errors_on(cs2)
    end

    test "encouraged/discouraged nutrient name helpers bucket by direction" do
      {:ok, cond} = Health.upsert_condition(%{name: "Anti-Inflammatory"})
      encourage!(cond, "Omega-3")
      encourage!(cond, "Fiber")
      limit!(cond, "Saturated Fat")

      assert Enum.sort(Health.encouraged_nutrient_names_for_conditions([cond.id])) ==
               ["Fiber", "Omega-3"]

      assert Health.discouraged_nutrient_names_for_conditions([cond.id]) == ["Saturated Fat"]
    end
  end

  describe "list_conditions_for_presentation gate" do
    test "includes a condition backed only by a nutrient recommendation" do
      {:ok, cond} = Health.upsert_condition(%{name: "Anti-Inflammatory", category: "pattern"})
      encourage!(cond, "Omega-3")

      names = Health.list_conditions_for_presentation() |> Enum.map(& &1.name)
      assert "Anti-Inflammatory" in names
    end
  end

  describe "NutrientTargets resolver" do
    test "resolves canonical label to the matching USDA nutrient rows" do
      omega = nutrient!("20:5 n-3")
      fiber = nutrient!("Fiber, total dietary")
      _unrelated = nutrient!("Protein")

      assert omega.id in NutrientTargets.nutrient_ids_for_label("Omega-3")
      assert fiber.id in NutrientTargets.nutrient_ids_for_label("Fiber")
      assert NutrientTargets.nutrient_ids_for_label("Nonexistent") == []
    end
  end

  describe "nutrient → food resolution" do
    setup do
      user = user_fixture()

      # An ingredient genuinely high in Omega-3, curated onto a species, in a recipe.
      salmon = ingredient_fixture(%{name: "Salmon #{System.unique_integer([:positive])}"})
      omega = nutrient!("20:5 n-3")
      Repo.insert!(%IngredientNutrient{ingredient_id: salmon.id, nutrient_id: omega.id, amount: 1.5})

      species =
        Repo.insert!(%FoundementalFoodSpecies{name: "Salmon sp #{System.unique_integer([:positive])}"})

      Repo.insert!(%FoundementalFood{
        foundemental_species_id: species.id,
        ingredient_id: salmon.id,
        usda_name: "salmon, raw"
      })

      mu = measurement_unit_fixture()

      {:ok, recipe} =
        Food.create_recipe(%{
          title: "Grilled salmon #{System.unique_integer([:positive])}",
          user_id: user.id,
          author: "a",
          cousine: "c",
          description: "d",
          servings: 2,
          language_name: "En",
          difficulty: 1,
          image_url: "https://example.com/img",
          cooking_time_lower_limit: 5,
          preperation_time_lower_limit: 5,
          recipe_ingredients: [
            %{ingredient_id: salmon.id, measurement_unit_id: mu.id, quantity: 100}
          ]
        })

      {:ok, cond} = Health.upsert_condition(%{name: "Anti-Inflammatory"})
      encourage!(cond, "Omega-3")

      %{cond: cond, species: species, recipe: recipe, ingredient: salmon}
    end

    test "encouraged_species_ids_for_conditions resolves the high-omega-3 species", ctx do
      assert ctx.species.id in Health.encouraged_species_ids_for_conditions([ctx.cond.id])
    end

    test "recipes_for_conditions_query includes the high-omega-3 recipe", ctx do
      ids =
        Health.recipes_for_conditions_query([ctx.cond.id]) |> Repo.all() |> Enum.map(& &1.id)

      assert ctx.recipe.id in ids
    end

    test "Food.filter_species matches via the nutrient species set", ctx do
      species_ids = Health.encouraged_species_ids_for_conditions([ctx.cond.id])

      names =
        Food.filter_species(condition_species_ids: species_ids) |> Enum.map(& &1.id)

      assert ctx.species.id in names
    end

    test "flags_for_recipes stamps a nutrient flag", ctx do
      flags = Health.flags_for_recipe(ctx.recipe.id, [ctx.cond.id])

      assert Enum.any?(flags, fn f ->
               f[:kind] == :nutrient and f.label == "Omega-3" and f.recommendation == "encourage"
             end)
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp encourage!(cond, nutrient_name), do: rec!(cond, nutrient_name, "encourage")
  defp limit!(cond, nutrient_name), do: rec!(cond, nutrient_name, "limit")

  defp rec!(cond, nutrient_name, direction) do
    {:ok, rec} =
      Health.add_nutrient_recommendation(cond.id, nutrient_name, %{
        recommendation: direction,
        severity: "moderate",
        source: "guideline",
        source_reference: %{"label" => "guideline", "url" => "https://example.com"}
      })

    rec
  end

  defp nutrient!(name) do
    Repo.insert!(%Nutrient{name: name, rank: System.unique_integer([:positive])})
  end
end
