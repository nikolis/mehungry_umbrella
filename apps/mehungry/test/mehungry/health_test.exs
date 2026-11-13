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
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
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
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
        })

      # same source → idempotent correction (severity replaced, still one row)
      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
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

  describe "flags_for_recipes/2 — recipe badges" do
    test "returns %{} when the user has opted into no conditions, and skips unrelated conditions" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, gout} = Health.upsert_condition(%{name: "Gout"})

      spinach = ingredient_fixture(%{name: "spinach"})
      recipe = recipe_with_ingredient(spinach)

      # No opted-in conditions → no DB hit, empty map (guard clause).
      assert Health.flags_for_recipes([recipe.id], []) == %{}
      # Opted into a condition with no recommendations → recipe not flagged.
      assert Health.flags_for_recipes([recipe.id], [gout.id]) == %{}
      # Empty recipe list → empty map (guard clause).
      assert Health.flags_for_recipes([], [kidney.id]) == %{}
    end
  end

  describe "flags_for_ingredients/2 — ingredient badges" do
    test "returns %{} for no opted-in conditions, and skips unrelated conditions" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, gout} = Health.upsert_condition(%{name: "Gout"})

      spinach = ingredient_fixture(%{name: "spinach"})

      # No opted-in conditions → no DB hit, empty map (guard clause).
      assert Health.flags_for_ingredients([spinach.id], []) == %{}
      # Opted into a condition with no recommendations → ingredient not flagged.
      assert Health.flags_for_ingredients([spinach.id], [gout.id]) == %{}
      # Empty ingredient list → empty map (guard clause).
      assert Health.flags_for_ingredients([], [kidney.id]) == %{}
    end
  end

  describe "recipes_for_conditions_query/1 — recipes good for a condition" do
    test "a condition with no encouraged (resolvable) advice matches no recipes" do
      {:ok, gout} = Health.upsert_condition(%{name: "Gout"})
      {:ok, purine} = Food.upsert_compound(%{name: "Purine", compound_type: "purine"})

      {:ok, _} =
        Health.add_recommendation(gout.id, purine.id, %{
          recommendation: "avoid",
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
        })

      liver = ingredient_fixture(%{name: "liver"})
      _recipe = recipe_with_ingredient(liver)

      assert [] == Health.recipes_for_conditions_query([gout.id]) |> Mehungry.Repo.all()
    end

    test "empty condition list falls back to all image-bearing recipes" do
      lemon = ingredient_fixture(%{name: "lemon"})
      recipe = recipe_with_ingredient(lemon)

      ids =
        []
        |> Health.recipes_for_conditions_query()
        |> Mehungry.Repo.all()
        |> Enum.map(& &1.id)

      assert recipe.id in ids
    end
  end

  describe "DB-content localization (el)" do
    setup do
      {:ok, _} = Mehungry.Languages.create_language(%{name: "el"})
      :ok
    end

    test "get_condition/2 overlays the el name + description, falling back per field" do
      {:ok, condition} =
        Health.create_condition(%{name: "Kidney Stones", description: "Mineral deposits."})

      {:ok, _} =
        %Mehungry.Health.ConditionTranslation{}
        |> Mehungry.Health.ConditionTranslation.changeset(%{
          condition_id: condition.id,
          language_name: "el",
          name: "Πέτρες στα Νεφρά"
        })
        |> Mehungry.Repo.insert()

      # el overlays the translated name; description has no el row → base value kept.
      localized = Health.get_condition(condition.id, "el")
      assert localized.name == "Πέτρες στα Νεφρά"
      assert localized.description == "Mineral deposits."

      # nil / "en" return the base record untouched.
      assert Health.get_condition(condition.id).name == "Kidney Stones"
      assert Health.get_condition(condition.id, "en").name == "Kidney Stones"
    end

    test "list_conditions_for_presentation/1 localizes each listed condition" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
        })

      {:ok, _} =
        %Mehungry.Health.ConditionTranslation{}
        |> Mehungry.Health.ConditionTranslation.changeset(%{
          condition_id: kidney.id,
          language_name: "el",
          name: "Πέτρες στα Νεφρά"
        })
        |> Mehungry.Repo.insert()

      assert [%{name: "Πέτρες στα Νεφρά"}] = Health.list_conditions_for_presentation("el")
    end

    test "species_for_condition/3 finds a legacy \"Gr\" species translation via the el locale" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones"})

      {:ok, species} =
        Food.create_foundemental_species(%{
          "name" => "Spinach",
          "scientific_name" => "Spinacia oleracea"
        })

      # A directly-curated food recommendation (ConditionStateRecommendation with a
      # species_id, no backing compound) — the surviving species resolution path.
      {:ok, _} =
        %Mehungry.Health.ConditionStateRecommendation{}
        |> Mehungry.Health.ConditionStateRecommendation.changeset(%{
          condition_id: kidney.id,
          species_id: species.id,
          recommendation: "avoid",
          source: "manual",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"},
          dedup_key: "kidney-spinach-avoid-#{System.unique_integer([:positive])}"
        })
        |> Mehungry.Repo.insert()

      # Older species rows predate the ISO migration and live under legacy "Gr"
      # (seeded by DataCase) — the "el" locale must still resolve them.
      {:ok, _} =
        %Mehungry.Food.FoundementalFoodSpeciesTranslation{}
        |> Mehungry.Food.FoundementalFoodSpeciesTranslation.changeset(%{
          foundemental_species_id: species.id,
          language_name: "Gr",
          name: "Σπανάκι"
        })
        |> Mehungry.Repo.insert()

      assert [%{species: %{name: "Σπανάκι"}}] = Health.species_for_condition(kidney.id, nil, "el")
    end

    test "recommendations_for_condition/2 overlays the el compound name" do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
        })

      {:ok, _} =
        %Mehungry.Food.CompoundTranslation{}
        |> Mehungry.Food.CompoundTranslation.changeset(%{
          compound_id: oxalate.id,
          language_name: "el",
          name: "Οξαλικό"
        })
        |> Mehungry.Repo.insert()

      assert [%{compound: %{name: "Οξαλικό"}}] =
               Health.recommendations_for_condition(kidney.id, "el")

      # Base language is untouched.
      assert [%{compound: %{name: "Oxalate"}}] =
               Health.recommendations_for_condition(kidney.id)
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
