defmodule Mehungry.HealthTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures
  import Mehungry.AccountsFixtures

  alias Mehungry.Food
  alias Mehungry.Health
  alias Mehungry.Health.{Condition, CompoundRecommendation}

  describe "condition registry" do
    test "create + get_by_name" do
      {:ok, condition} =
        Health.create_condition(%{
          name: "Kidney Stones",
          synonyms: ["Nephrolithiasis", "Renal calculi"],
          category: "renal",
          description: "Hard deposits of minerals in the kidneys."
        })

      assert condition.name == "Kidney Stones"
      assert condition.category == "renal"
      assert "Nephrolithiasis" in condition.synonyms
      assert Health.get_condition_by_name("Kidney Stones").id == condition.id
    end

    test "name is required and unique" do
      assert {:error, changeset} = Health.create_condition(%{category: "renal"})
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      {:ok, _} = Health.create_condition(%{name: "Gout"})
      assert {:error, changeset} = Health.create_condition(%{name: "Gout"})
      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "upsert_condition dedupes on name" do
      {:ok, first} = Health.upsert_condition(%{name: "IBS"})
      {:ok, second} = Health.upsert_condition(%{name: "IBS"})

      assert first.id == second.id
      assert Health.list_conditions() |> Enum.filter(&(&1.name == "IBS")) |> length() == 1
    end

    test "list_conditions_by_category filters" do
      {:ok, _} = Health.create_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, _} = Health.create_condition(%{name: "IBS", category: "digestive"})

      assert [%Condition{name: "Kidney Stones"}] = Health.list_conditions_by_category("renal")
    end
  end

  describe "compound recommendations" do
    test "Kidney Stones: avoid Oxalate" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, rec} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          evidence_level: "strong",
          source: "guideline"
        })

      assert rec.recommendation == "avoid"
      assert rec.severity == "high"

      assert [%CompoundRecommendation{recommendation: "avoid", compound: %{name: "Oxalate"}}] =
               Health.recommendations_for_condition(kidney.id)
    end

    test "IBS: limit FODMAP" do
      {:ok, ibs} = Health.upsert_condition(%{name: "IBS", category: "digestive"})
      {:ok, fodmap} = Food.upsert_compound(%{name: "Fructan", compound_type: "fodmap"})

      {:ok, _rec} =
        Health.add_recommendation(
          %{name: "IBS"},
          fodmap.id,
          %{recommendation: "limit", source: "literature", notes: "applies to high-FODMAP foods"}
        )

      assert [%CompoundRecommendation{recommendation: "limit", condition: %{name: "IBS"}}] =
               Health.recommendations_for_compound(fodmap.id)

      # add_recommendation with condition attrs reused the existing condition
      assert Health.list_conditions() |> Enum.filter(&(&1.name == "IBS")) |> length() == 1
      assert ibs.id == Health.get_condition_by_name("IBS").id
    end

    test "required fields and enum inclusion are validated" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      assert {:error, changeset} =
               Health.create_recommendation(%{condition_id: kidney.id, compound_id: oxalate.id})

      errors = errors_on(changeset)
      assert %{recommendation: ["can't be blank"]} = errors
      assert %{source: ["can't be blank"]} = errors

      assert {:error, changeset} =
               Health.create_recommendation(%{
                 condition_id: kidney.id,
                 compound_id: oxalate.id,
                 recommendation: "nuke",
                 severity: "apocalyptic",
                 evidence_level: "vibes",
                 source: "hearsay"
               })

      errors = errors_on(changeset)
      assert %{recommendation: ["is invalid"]} = errors
      assert %{severity: ["is invalid"]} = errors
      assert %{evidence_level: ["is invalid"]} = errors
      assert %{source: ["is invalid"]} = errors
    end

    test "upsert dedupes on (condition, compound, source); a new source is a distinct row" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "moderate",
          source: "guideline"
        })

      # same source → idempotent correction (severity replaced, still one row)
      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          source: "guideline"
        })

      # different source → distinct row
      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "limit",
          source: "ai"
        })

      recs = Health.recommendations_for_condition(kidney.id)
      assert length(recs) == 2
      guideline = Enum.find(recs, &(&1.source == "guideline"))
      assert guideline.severity == "high"
    end
  end

  # Curate `ingredient` onto a new species and assert `species high_in compound`.
  defp species_fact(ingredient, species_name, sci_name, compound, rel_type \\ "high_in") do
    {:ok, species} =
      Food.create_foundemental_species(%{"name" => species_name, "scientific_name" => sci_name})

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, ingredient.id, ingredient.name)

    {:ok, _} =
      Food.upsert_species_relationship(%{
        foundemental_species_id: species.id,
        compound_id: compound.id,
        relationship_type: rel_type,
        source: "literature",
        confidence: 0.9
      })

    species
  end

  describe "condition resolution — species facts, ingredients derived through species" do
    test "species_for_condition surfaces the species via the shared compound; ingredients derive through it" do
      # Advice layer: Kidney Stones → avoid → Oxalate
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          evidence_level: "strong",
          source: "guideline"
        })

      # Species-facts layer: Spinach species high_in Oxalate (with a curated ingredient).
      spinach = ingredient_fixture(%{name: "spinach"})
      species = species_fact(spinach, "Spinach", "Spinacia oleracea", oxalate)

      # Primary read resolves to the species through the shared compound.
      assert [srow] = Health.species_for_condition(kidney.id, :avoid)
      assert srow.species.id == species.id
      assert srow.compound.name == "Oxalate"
      assert srow.recommendation == "avoid"
      assert srow.severity == "high"

      # Ingredients are derived strictly through the species.
      assert [irow] = Health.ingredients_for_condition(kidney.id, :avoid)
      assert irow.ingredient.id == spinach.id
      assert irow.compound.name == "Oxalate"
    end

    test "filters by recommendation and returns all when unfiltered" do
      {:ok, cond} = Health.upsert_condition(%{name: "Gout"})
      {:ok, purine} = Food.upsert_compound(%{name: "Purine", compound_type: "purine"})

      {:ok, _} =
        Health.add_recommendation(cond.id, purine.id, %{
          recommendation: "limit",
          source: "guideline"
        })

      liver = ingredient_fixture(%{name: "liver"})
      _species = species_fact(liver, "Cattle", "Bos taurus", purine)

      assert [%{species: %{name: "Cattle"}}] = Health.species_for_condition(cond.id, :limit)
      assert [%{ingredient: %{name: "liver"}}] = Health.ingredients_for_condition(cond.id, :limit)
      assert [] == Health.ingredients_for_condition(cond.id, :avoid)
      assert [%{ingredient: %{name: "liver"}}] = Health.ingredients_for_condition(cond.id)
    end
  end

  describe "flags_for_recipes/2 — recipe badges" do
    test "flags a recipe whose ingredient carries a compound recommended for an opted-in condition" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          source: "guideline"
        })

      spinach = ingredient_fixture(%{name: "spinach"})
      species_fact(spinach, "Spinach", "Spinacia oleracea", oxalate)

      recipe = recipe_with_ingredient(spinach)

      flags = Health.flags_for_recipes([recipe.id], [kidney.id])
      assert [flag] = Map.fetch!(flags, recipe.id)
      assert flag.condition.id == kidney.id
      assert flag.compound.name == "Oxalate"
      assert flag.recommendation == "avoid"
      assert flag.severity == "high"

      # Single-recipe convenience wrapper.
      assert [%{compound: %{name: "Oxalate"}}] = Health.flags_for_recipe(recipe.id, [kidney.id])
    end

    test "returns %{} when the user has opted into no conditions, and skips unrelated conditions" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, gout} = Health.upsert_condition(%{name: "Gout"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          source: "guideline"
        })

      spinach = ingredient_fixture(%{name: "spinach"})
      species_fact(spinach, "Spinach", "Spinacia oleracea", oxalate)
      recipe = recipe_with_ingredient(spinach)

      # No opted-in conditions → no DB hit, empty map.
      assert Health.flags_for_recipes([recipe.id], []) == %{}
      # Opted into an unrelated condition → recipe not flagged.
      assert Health.flags_for_recipes([recipe.id], [gout.id]) == %{}
    end
  end

  describe "flags_for_ingredients/2 — ingredient badges" do
    test "flags an ingredient carrying a compound recommended for an opted-in condition" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          source: "guideline"
        })

      spinach = ingredient_fixture(%{name: "spinach"})
      species_fact(spinach, "Spinach", "Spinacia oleracea", oxalate)

      flags = Health.flags_for_ingredients([spinach.id], [kidney.id])
      assert [flag] = Map.fetch!(flags, spinach.id)
      assert flag.condition.id == kidney.id
      assert flag.compound.name == "Oxalate"
      assert flag.recommendation == "avoid"
      assert flag.severity == "high"

      # Single-ingredient convenience wrapper.
      assert [%{compound: %{name: "Oxalate"}}] = Health.flags_for_ingredient(spinach.id, [kidney.id])
    end

    test "returns %{} for no opted-in conditions, and skips unrelated conditions" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, gout} = Health.upsert_condition(%{name: "Gout"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          source: "guideline"
        })

      spinach = ingredient_fixture(%{name: "spinach"})
      species_fact(spinach, "Spinach", "Spinacia oleracea", oxalate)

      # No opted-in conditions → no DB hit, empty map.
      assert Health.flags_for_ingredients([spinach.id], []) == %{}
      # Opted into an unrelated condition → ingredient not flagged.
      assert Health.flags_for_ingredients([spinach.id], [gout.id]) == %{}
      # Empty ingredient list → empty map.
      assert Health.flags_for_ingredients([], [kidney.id]) == %{}
    end
  end

  # A recipe using `ingredient` (recipe_fixture builds its own ingredient, so we
  # create one directly to control the ingredient→species→compound chain).
  defp recipe_with_ingredient(ingredient) do
    user = user_fixture()
    mu = measurement_unit_fixture()

    {:ok, recipe} =
      Food.create_recipe(%{
        title: "flagged recipe",
        user_id: user.id,
        author: "author",
        cousine: "cuisine",
        description: "desc",
        servings: 2,
        language_name: "En",
        difficulty: 1,
        image_url: "https://example.com/i.jpg",
        cooking_time_lower_limit: 5,
        preperation_time_lower_limit: 5,
        recipe_ingredients: [
          %{ingredient_id: ingredient.id, measurement_unit_id: mu.id, quantity: 5}
        ]
      })

    recipe
  end
end
