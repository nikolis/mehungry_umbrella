defmodule Mehungry.Food.SpeciesEnrichmentTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesFact

  defp species(name) do
    {:ok, sp} = Food.create_foundemental_species(%{name: name})
    sp
  end

  describe "record_wikidata_facts/2" do
    test "fans a fetch result into pending facts, cited to the Q-id" do
      sp = species("Apple")

      result = %{
        qid: "Q89",
        origin_region: "Central Asia",
        descriptions: %{"en" => "species of fruit", "el" => "είδος φρούτου"},
        wikipedia_urls: %{"en" => "https://en.wikipedia.org/wiki/Apple"}
      }

      assert 4 == Food.record_species_wikidata_facts(sp.id, result)

      facts = Repo.all(SpeciesFact)
      assert length(facts) == 4
      assert Enum.all?(facts, &(&1.status == "pending"))
      assert Enum.all?(facts, & &1.enrichment_source_id)

      origin = Enum.find(facts, &(&1.fact_key == "origin_region"))
      assert origin.value_text == "Central Asia"
      assert origin.locale == ""

      descriptions = Enum.filter(facts, &(&1.fact_key == "description"))
      assert Enum.map(descriptions, & &1.locale) |> Enum.sort() == ["el", "en"]
    end

    test "records no source when the fetch had no Q-id, and skips empty values" do
      sp = species("Mystery")
      assert 1 == Food.record_species_wikidata_facts(sp.id, %{origin_region: "Nowhere"})

      [fact] = Repo.all(SpeciesFact)
      assert fact.fact_key == "origin_region"
      assert is_nil(fact.enrichment_source_id)
    end

    test "is idempotent on (species, key, locale) — re-fetch upserts, never duplicates" do
      sp = species("Apple")
      base = %{qid: "Q89", origin_region: "Kazakhstan"}

      assert 1 == Food.record_species_wikidata_facts(sp.id, base)
      assert 1 == Food.record_species_wikidata_facts(sp.id, %{base | origin_region: "Central Asia"})

      assert [%{value_text: "Central Asia"}] = Repo.all(SpeciesFact)
    end
  end

  describe "record_faostat_facts/2" do
    test "stores one top_producers fact with the producers list and FAOSTAT citation" do
      sp = species("Apple")

      producers = [
        %{country: "China", tonnes: 47_571_100.0, year: 2022},
        %{country: "Turkey", tonnes: 4_817_500.0, year: 2022}
      ]

      assert 1 == Food.record_species_faostat_facts(sp.id, producers)

      [fact] = Repo.all(SpeciesFact) |> Repo.preload(:enrichment_source)
      assert fact.fact_key == "top_producers"
      assert fact.value_json["producers"] |> length() == 2
      assert fact.enrichment_source.identifier == "faostat_qcl"
      assert fact.value_text =~ "China"
    end

    test "records nothing for an empty producers list" do
      sp = species("Apple")
      assert 0 == Food.record_species_faostat_facts(sp.id, [])
      assert [] == Repo.all(SpeciesFact)
    end
  end

  describe "promote / reject" do
    setup do
      sp = species("Apple")
      Food.record_species_wikidata_facts(sp.id, %{qid: "Q89", origin_region: "Central Asia"})
      [fact] = Food.list_pending_species_facts()
      %{sp: sp, fact: fact}
    end

    test "promote surfaces the fact; reject hides it", %{sp: sp, fact: fact} do
      assert Food.promoted_species_facts_for_species(sp.id) == %{}

      {:ok, _} = Food.promote_species_fact(fact.id)
      surfaced = Food.promoted_species_facts_for_species(sp.id)
      assert surfaced["origin_region"].value_text == "Central Asia"

      {:ok, _} = Food.reject_species_fact(fact.id)
      assert Food.promoted_species_facts_for_species(sp.id) == %{}
    end

    test "a rejected fact is not resurrected by a re-fetch", %{sp: sp, fact: fact} do
      {:ok, _} = Food.reject_species_fact(fact.id)
      Food.record_species_wikidata_facts(sp.id, %{qid: "Q89", origin_region: "Central Asia"})

      assert [%{status: "rejected"}] = Repo.all(SpeciesFact)
      assert Food.list_pending_species_facts() == []
    end
  end

  describe "promoted_facts_for_species/2 locale resolution" do
    test "prefers the requested locale, falls back to en, then locale-independent" do
      sp = species("Apple")

      Food.record_species_wikidata_facts(sp.id, %{
        qid: "Q89",
        origin_region: "Central Asia",
        descriptions: %{"en" => "english", "el" => "greek"}
      })

      Enum.each(Food.list_pending_species_facts(), &Food.promote_species_fact(&1.id))

      el = Food.promoted_species_facts_for_species(sp.id, "el")
      assert el["description"].value_text == "greek"
      # origin_region is locale-independent ("") and still resolves under el
      assert el["origin_region"].value_text == "Central Asia"

      # a locale with no translation falls back to en
      fr = Food.promoted_species_facts_for_species(sp.id, "fr")
      assert fr["description"].value_text == "english"
    end
  end
end
