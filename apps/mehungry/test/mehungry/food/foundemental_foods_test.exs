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

  describe "ingredient_icons/1" do
    test "a curated ingredient resolves through its species", %{species: species, spinach: spinach} do
      # Spinach species → 🥬 from the species name keyword.
      assert Food.ingredient_icons([spinach.id]) == %{spinach.id => "🥬"}

      # A curator override on the species wins for its curated ingredients.
      {:ok, _} = Food.update_foundemental_species(species, %{"icon" => "🦄"})
      assert Food.ingredient_icons([spinach.id]) == %{spinach.id => "🦄"}
    end

    test "a non-curated ingredient derives from its own name" do
      tomato = ingredient_fixture(%{name: "Tomato, raw"})
      assert Food.ingredient_icons([tomato.id]) == %{tomato.id => "🍅"}
    end

    test "an unmatched ingredient falls back to the generic default" do
      blargh = ingredient_fixture(%{name: "Blarghium zzz"})
      assert Food.ingredient_icons([blargh.id]) == %{blargh.id => "🥗"}
    end

    test "empty input returns an empty map" do
      assert Food.ingredient_icons([]) == %{}
    end

    test "species_by_ingredient_ids/1 returns the species struct keyed by ingredient id",
         %{species: species, spinach: spinach} do
      map = Food.species_by_ingredient_ids([spinach.id])
      assert map[spinach.id].id == species.id
    end
  end

  describe "update_species/2 (icon override)" do
    test "persists a curator's icon override", %{species: species} do
      {:ok, updated} = Food.update_foundemental_species(species, %{"icon" => "🥗"})
      assert updated.icon == "🥗"
      assert Food.species_icon(updated) == "🥗"
    end

    test "clearing the override falls back to the derived default", %{species: species} do
      {:ok, with_icon} = Food.update_foundemental_species(species, %{"icon" => "🥗"})
      {:ok, cleared} = Food.update_foundemental_species(with_icon, %{"icon" => nil})
      assert cleared.icon == nil
      # Spinach derives 🥬 from its name.
      assert Food.species_icon(cleared) == "🥬"
    end
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

  describe "private species are hidden from public surfaces" do
    setup %{} do
      {:ok, hidden} =
        Food.create_foundemental_species(%{
          "name" => "Secret Kale",
          "alternative_name" => "hidden greens",
          "private" => true,
          "translations" => [%{"name" => "Κρυφό", "language_name" => "el"}]
        })

      %{hidden: hidden}
    end

    test "excluded from the paginated feed", %{hidden: hidden} do
      {entries, _} = Food.list_species_paginated()
      refute Enum.any?(entries, &(&1.id == hidden.id))
    end

    test "excluded from the Greek translated feed", %{hidden: hidden} do
      {entries, _} = Food.list_species_paginated_translated("el")
      refute Enum.any?(entries, &(&1.id == hidden.id))
    end

    test "excluded from the compound filter / browse list", %{hidden: hidden, species: public} do
      ids = Food.filter_species([]) |> Enum.map(& &1.id)
      assert public.id in ids
      refute hidden.id in ids
    end

    test "excluded from the A–Z directory", %{hidden: hidden} do
      refute Enum.any?(Food.list_species_for_directory(), &(&1.id == hidden.id))
    end

    test "excluded from name search (EN) and translation search (EL)", %{hidden: hidden} do
      refute Enum.any?(SpeciesSearch.search("Secret"), &(&1.id == hidden.id))
      refute Enum.any?(SpeciesSearch.search("hidden"), &(&1.id == hidden.id))
      refute Enum.any?(SpeciesSearch.search_in_language("Κρυφ", "el"), &(&1.id == hidden.id))
    end

    test "its detail page / API show 404s (slug lookup returns nil)", %{hidden: hidden} do
      assert Food.get_species_by_slug("Secret-Kale") == nil
      assert Food.get_species_by_slug("Κρυφό") == nil
      # Sanity: a public species still resolves.
      refute is_nil(Food.get_species_by_slug("Spinach"))
      _ = hidden
    end

    test "the mobile-API public list/search exclude it but admin scope includes it", %{
      hidden: hidden
    } do
      refute Enum.any?(Food.list_public_foundemental_species(), &(&1.id == hidden.id))
      refute Enum.any?(Food.search_public_species("Secret"), &(&1.id == hidden.id))

      # Admin curation surfaces still see private species.
      assert Enum.any?(Food.list_foundemental_species(), &(&1.id == hidden.id))
      assert Enum.any?(Food.search_species("Secret"), &(&1.id == hidden.id))
    end
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
          source: "guideline",
          source_reference: %{"label" => "Clinical guideline", "url" => "https://example.org"}
        })

      assert [rec] = Health.recommendations_for_species(species.id)
      assert rec.condition.id == kidney.id
      assert rec.compound.name == "Oxalate"
      assert rec.recommendation == "avoid"
      assert rec.severity == "high"
    end
  end
end
