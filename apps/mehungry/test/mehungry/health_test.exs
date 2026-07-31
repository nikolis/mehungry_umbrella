defmodule Mehungry.HealthTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

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

  describe "ingredients_for_condition/2 — cross-layer composition" do
    test "surfaces the food via the shared compound, with no condition→ingredient FK" do
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

      # Independent food-facts layer: Spinach high_in Oxalate
      spinach = ingredient_fixture(%{name: "spinach"})

      {:ok, _} =
        Food.add_compound_to_ingredient(
          spinach.id,
          %{name: "Oxalate", compound_type: "oxalate"},
          %{relationship_type: "high_in", source: "literature", confidence: 0.9}
        )

      # Composition resolves the food through the compound.
      assert [row] = Health.ingredients_for_condition(kidney.id, :avoid)
      assert row.ingredient.id == spinach.id
      assert row.compound.name == "Oxalate"
      assert row.recommendation == "avoid"
      assert row.severity == "high"
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

      {:ok, _} =
        Food.add_compound_to_ingredient(
          liver.id,
          %{name: "Purine", compound_type: "purine"},
          %{relationship_type: "high_in", source: "literature"}
        )

      assert [%{ingredient: %{name: "liver"}}] = Health.ingredients_for_condition(cond.id, :limit)
      assert [] == Health.ingredients_for_condition(cond.id, :avoid)
      assert [%{ingredient: %{name: "liver"}}] = Health.ingredients_for_condition(cond.id)
    end
  end
end
