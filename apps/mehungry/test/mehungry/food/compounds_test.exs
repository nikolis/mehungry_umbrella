defmodule Mehungry.Food.CompoundsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.Compound

  describe "compound registry" do
    test "create + get_by_name" do
      {:ok, compound} =
        Food.create_compound(%{
          name: "Oxalate",
          compound_type: "oxalate",
          synonyms: ["Oxalic acid", "Ethanedioic acid"],
          properties: %{"molecular_formula" => "C2H2O4"}
        })

      assert compound.name == "Oxalate"
      assert compound.compound_type == "oxalate"
      assert Food.get_compound_by_name("Oxalate").id == compound.id
    end

    test "upsert_compound dedupes on name" do
      {:ok, first} = Food.upsert_compound(%{name: "Sulforaphane", compound_type: "other"})
      {:ok, second} = Food.upsert_compound(%{name: "Sulforaphane", compound_type: "other"})

      assert first.id == second.id
      assert Food.list_compounds() |> Enum.filter(&(&1.name == "Sulforaphane")) |> length() == 1
    end

    test "synonyms array and structural properties map round-trip through the DB" do
      {:ok, compound} =
        Food.create_compound(%{
          name: "Quercetin",
          compound_type: "polyphenol",
          synonyms: ["Sophoretin", "Meletin"],
          properties: %{"molecular_formula" => "C15H10O7", "smiles" => "c1cc..."}
        })

      reloaded = Food.get_compound!(compound.id)
      assert reloaded.synonyms == ["Sophoretin", "Meletin"]
      assert reloaded.properties["molecular_formula"] == "C15H10O7"
    end

    test "list_compounds_by_type filters by compound_type" do
      Food.create_compound(%{name: "Oxalate", compound_type: "oxalate"})
      Food.create_compound(%{name: "Quercetin", compound_type: "polyphenol"})

      assert [%Compound{name: "Quercetin"}] = Food.list_compounds_by_type("polyphenol")
    end

    test "compound_type must be a known value" do
      {:error, changeset} = Food.create_compound(%{name: "Mystery", compound_type: "nonsense"})
      assert %{compound_type: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "cross-database identifiers" do
    setup do
      {:ok, compound} = Food.upsert_compound(%{name: "Oxalic acid", compound_type: "oxalate"})
      %{compound: compound}
    end

    test "upsert + look up by (namespace, identifier)", %{compound: compound} do
      {:ok, _} =
        Food.upsert_compound_identifier(%{
          compound_id: compound.id,
          namespace: "pubchem",
          identifier: "971",
          is_primary: true,
          source: "pubchem"
        })

      found = Food.get_compound_by_identifier("pubchem", "971")
      assert found.id == compound.id
      # Integer identifiers are coerced to string for lookup.
      assert Food.get_compound_by_identifier("pubchem", 971).id == compound.id
    end

    test "the same (namespace, identifier) always resolves to one compound", %{compound: compound} do
      {:ok, other} = Food.upsert_compound(%{name: "Ethanedioic acid", compound_type: "oxalate"})

      {:ok, first} =
        Food.upsert_compound_identifier(%{
          compound_id: compound.id,
          namespace: "chebi",
          identifier: "CHEBI:16995"
        })

      # Re-asserting the same external id upserts the existing row (idempotent).
      {:ok, second} =
        Food.upsert_compound_identifier(%{
          compound_id: other.id,
          namespace: "chebi",
          identifier: "CHEBI:16995"
        })

      assert first.id == second.id
      assert length(Food.list_compound_identifiers(compound.id)) == 0
      assert [%{namespace: "chebi"}] = Food.list_compound_identifiers(other.id)
    end

    test "namespace must be a known value", %{compound: compound} do
      {:error, changeset} =
        Food.upsert_compound_identifier(%{
          compound_id: compound.id,
          namespace: "nonsense",
          identifier: "x"
        })

      assert %{namespace: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "ingredient ↔ compound relationships" do
    test "Spinach contains Oxalate" do
      spinach = ingredient_fixture(%{name: "spinach"})

      {:ok, rel} =
        Food.add_compound_to_ingredient(
          spinach.id,
          %{name: "Oxalate", compound_type: "oxalate"},
          %{relationship_type: "contains", source: "literature", confidence: 0.95}
        )

      assert rel.relationship_type == "contains"
      assert [%Compound{name: "Oxalate"}] = Food.list_compounds_for_ingredient(spinach.id)
    end

    test "Broccoli contains Sulforaphane" do
      broccoli = ingredient_fixture(%{name: "broccoli"})

      {:ok, _rel} =
        Food.add_compound_to_ingredient(
          broccoli.id,
          %{name: "Sulforaphane", compound_type: "other"},
          %{relationship_type: "contains", source: "literature"}
        )

      assert [%Compound{name: "Sulforaphane", compound_type: "other"}] =
               Food.list_compounds_for_ingredient(broccoli.id)
    end

    test "list_ingredients_for_compound returns the linked ingredients" do
      spinach = ingredient_fixture(%{name: "spinach"})
      {:ok, compound} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Food.link_compound(%{
          ingredient_id: spinach.id,
          compound_id: compound.id,
          relationship_type: "contains",
          source: "manual"
        })

      assert [ingredient] = Food.list_ingredients_for_compound(compound.id)
      assert ingredient.id == spinach.id
    end

    test "never-overwrite: same (ingredient, compound, relationship_type, source) dedupes" do
      spinach = ingredient_fixture(%{name: "spinach"})
      {:ok, compound} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      base = %{
        ingredient_id: spinach.id,
        compound_id: compound.id,
        relationship_type: "contains",
        source: "literature"
      }

      {:ok, first} = Food.upsert_compound_relationship(Map.put(base, :confidence, 0.5))
      {:ok, second} = Food.upsert_compound_relationship(Map.put(base, :confidence, 0.9))

      assert first.id == second.id
      assert [only] = Food.list_compound_relationships(spinach.id)
      assert only.confidence == 0.9
    end

    test "a different source or relationship_type is a distinct fact" do
      spinach = ingredient_fixture(%{name: "spinach"})
      {:ok, compound} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      base = %{ingredient_id: spinach.id, compound_id: compound.id}

      {:ok, _} =
        Food.link_compound(
          Map.merge(base, %{relationship_type: "contains", source: "literature"})
        )

      {:ok, _} =
        Food.link_compound(Map.merge(base, %{relationship_type: "high_in", source: "literature"}))

      {:ok, _} =
        Food.link_compound(Map.merge(base, %{relationship_type: "contains", source: "ai"}))

      assert length(Food.list_compound_relationships(spinach.id)) == 3
    end

    test "relationship_type and source must be known values" do
      spinach = ingredient_fixture(%{name: "spinach"})
      {:ok, compound} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:error, changeset} =
        Food.link_compound(%{
          ingredient_id: spinach.id,
          compound_id: compound.id,
          relationship_type: "cures",
          source: "wishful"
        })

      assert %{relationship_type: ["is invalid"], source: ["is invalid"]} = errors_on(changeset)
    end
  end
end
