defmodule Mehungry.Food.FoundementalFoodsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesSearch
  alias Mehungry.Health
  alias Mehungry.Languages
  alias Mehungry.Literature

  setup do
    {:ok, _el} = Languages.create_language(%{name: "el"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea",
        "family" => "Amaranthaceae",
        "translations" => [%{"name" => "Σπανάκι", "language_name" => "el"}]
      })

    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    %{species: species, spinach: spinach}
  end

  describe "translations (cast_assoc through create_species)" do
    test "the translation is persisted and readable", %{species: species} do
      assert Food.find_species_translation("el", species.id) == ["Σπανάκι"]
      assert Food.find_species_translation("en", species.id) == []
    end
  end

  describe "get_species_by_slug/1" do
    test "resolves by English name (hyphenated slug), preloading foods + translations", %{
      species: species,
      spinach: spinach
    } do
      found = Food.get_species_by_slug("Spinach")
      assert found.id == species.id
      assert [food] = found.foundemental_foods
      assert food.ingredient.id == spinach.id
      assert Enum.map(found.translations, & &1.name) == ["Σπανάκι"]
    end

    test "falls back to a translated name", %{species: species} do
      assert Food.get_species_by_slug("Σπανάκι").id == species.id
    end

    test "returns nil for an unknown slug" do
      assert Food.get_species_by_slug("no-such-species") == nil
    end
  end

  describe "pagination" do
    test "list_species_paginated returns the species", %{species: species} do
      {entries, _cursor} = Food.list_species_paginated()
      assert Enum.any?(entries, &(&1.id == species.id))
    end

    test "list_species_paginated_translated only returns species with a translation", %{
      species: species
    } do
      {:ok, other} = Food.create_foundemental_species(%{"name" => "Kale"})

      {entries, _} = Food.list_species_paginated_translated("el")
      ids = Enum.map(entries, & &1.id)
      assert species.id in ids
      refute other.id in ids
    end
  end

  describe "SpeciesSearch" do
    test "search/1 matches on name, prefix first", %{species: species} do
      results = SpeciesSearch.search("spin")
      assert Enum.any?(results, &(&1.id == species.id))
    end

    test "search_in_language/2 matches translations and returns id/name maps", %{
      species: species
    } do
      assert [%{id: id, name: "Σπανάκι"}] = SpeciesSearch.search_in_language("Σπαν", "el")
      assert id == species.id
    end

    test "empty term returns []", do: assert(SpeciesSearch.search("") == [])
  end

  describe "cross-context aggregations" do
    test "Literature.list_studies_for_species unions studies across the species' ingredients",
         %{species: species, spinach: spinach} do
      {:ok, study} = Literature.upsert_study(%{pmid: 555_001, title: "Spinach study"})

      {:ok, _} =
        Literature.link_study_ingredient(%{
          study_id: study.id,
          ingredient_id: spinach.id,
          search_term: "spinach oxalate"
        })

      assert [found] = Literature.list_studies_for_species(species.id)
      assert found.id == study.id
    end

    test "Health.recommendations_for_species surfaces advice via the species' compounds",
         %{species: species} do
      {:ok, kidney} = Health.upsert_condition(%{name: "Kidney Stones", category: "renal"})
      {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})

      {:ok, _} =
        Food.upsert_species_relationship(%{
          foundemental_species_id: species.id,
          compound_id: oxalate.id,
          relationship_type: "high_in",
          source: "literature"
        })

      {:ok, _} =
        Health.add_recommendation(kidney.id, oxalate.id, %{
          recommendation: "avoid",
          severity: "high",
          evidence_level: "strong",
          source: "guideline"
        })

      assert [rec] = Health.recommendations_for_species(species.id)
      assert rec.condition.id == kidney.id
      assert rec.compound.name == "Oxalate"
      assert rec.recommendation == "avoid"
      assert rec.severity == "high"
    end
  end
end
