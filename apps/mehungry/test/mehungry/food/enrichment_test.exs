# Canned USDA record in the shape FdcClient.fetch_food/1 returns and
# FoodParser.reconcile_ingredient/2 expects. Carries foodPortions + foodNutrients
# so reconciling replaces those child rows — the contrast the reconciliation-safety
# test relies on. Kept in this file so it runs in isolation.
defmodule Mehungry.Food.EnrichReconFixtures do
  def salt_attrs do
    %{
      "description" => "Salt, table",
      "dataType" => "Foundation",
      "foodClass" => "FinalFood",
      "fdcId" => 999_999,
      "ndbNumber" => 2047,
      "publicationDate" => "4/1/2019",
      "nutrientConversionFactors" => [],
      "foodCategory" => %{"description" => "Spices and Herbs"},
      "foodPortions" => [
        %{
          "modifier" => "g",
          "gramWeight" => 100.0,
          "amount" => 1.0,
          "value" => 100.0,
          "id" => 1,
          "sequenceNumber" => 1,
          "minYearAcquired" => nil
        }
      ],
      "foodNutrients" => [
        %{
          "amount" => 38_758.0,
          "median" => nil,
          "dataPoints" => nil,
          "type" => "FoodNutrient",
          "nutrient" => %{
            "id" => 1093,
            "name" => "Sodium, Na",
            "number" => "307",
            "rank" => 5800,
            "unitName" => "mg"
          }
        }
      ]
    }
  end
end

defmodule Mehungry.Food.EnrichmentTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.EnrichReconFixtures
  alias Mehungry.ObanWorkers.IngredientReconciliationWorker
  alias Mehungry.Repo

  defmodule OkStub do
    def fetch_food(999_999), do: {:ok, EnrichReconFixtures.salt_attrs(), %{remaining: 100}}
    def fetch_food(_other), do: {:error, "no FDC results"}
  end

  defp use_fdc_client(module) do
    Application.put_env(:mehungry, :fdc_client, module)
    on_exit(fn -> Application.delete_env(:mehungry, :fdc_client) end)
  end

  describe "scientific properties" do
    test "create + list" do
      ing = ingredient_fixture(%{name: "blueberry"})

      {:ok, prop} =
        Food.create_scientific_property(%{
          ingredient_id: ing.id,
          property_key: "orac",
          value: 4669.0,
          unit: "umol_TE",
          basis: "per_100g",
          source: "literature"
        })

      assert prop.property_key == "orac"
      assert [^prop] = Food.list_scientific_properties(ing.id)
    end

    test "upsert is idempotent on (ingredient_id, property_key, source)" do
      ing = ingredient_fixture(%{name: "blueberry"})
      attrs = %{ingredient_id: ing.id, property_key: "orac", source: "literature"}

      {:ok, first} = Food.upsert_scientific_property(Map.put(attrs, :value, 4000.0))
      {:ok, second} = Food.upsert_scientific_property(Map.put(attrs, :value, 4669.0))

      assert first.id == second.id
      assert second.value == 4669.0
      assert [only] = Food.list_scientific_properties(ing.id)
      assert only.value == 4669.0
    end

    test "source must be a known provenance value" do
      ing = ingredient_fixture(%{name: "blueberry"})

      {:error, changeset} =
        Food.create_scientific_property(%{
          ingredient_id: ing.id,
          property_key: "orac",
          source: "bogus"
        })

      assert %{source: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "classifications and health attributes" do
    test "classification create + list" do
      ing = ingredient_fixture(%{name: "blueberry"})

      {:ok, cls} =
        Food.create_classification(%{
          ingredient_id: ing.id,
          scientific_name: "Vaccinium corymbosum",
          genus: "Vaccinium",
          species: "corymbosum",
          rank: "species",
          source: "external_db"
        })

      assert cls.genus == "Vaccinium"
      assert [^cls] = Food.list_classifications(ing.id)
    end

    test "health attribute create + list" do
      ing = ingredient_fixture(%{name: "wheat"})

      {:ok, attr} =
        Food.create_health_attribute(%{
          ingredient_id: ing.id,
          attribute: "allergen:gluten",
          value: "contains",
          source: "manual"
        })

      assert attr.attribute == "allergen:gluten"
      assert [^attr] = Food.list_health_attributes(ing.id)
    end
  end

  describe "citation registry" do
    test "upsert_enrichment_source find-or-creates on (source_type, identifier)" do
      attrs = %{source_type: "doi", identifier: "10.1234/abcd", title: "A study"}

      {:ok, first} = Food.upsert_enrichment_source(attrs)
      {:ok, second} = Food.upsert_enrichment_source(attrs)

      assert first.id == second.id
      assert length(Food.list_enrichment_sources()) == 1
    end
  end

  describe "list_enrichment/1 aggregate" do
    test "returns all three fact groups for an ingredient" do
      ing = ingredient_fixture(%{name: "blueberry"})

      {:ok, _} =
        Food.create_scientific_property(%{
          ingredient_id: ing.id,
          property_key: "orac",
          source: "literature"
        })

      {:ok, _} =
        Food.create_classification(%{
          ingredient_id: ing.id,
          scientific_name: "Vaccinium corymbosum",
          source: "external_db"
        })

      {:ok, _} =
        Food.create_health_attribute(%{
          ingredient_id: ing.id,
          attribute: "diet:vegan",
          source: "manual"
        })

      enrichment = Food.list_enrichment(ing.id)

      assert length(enrichment.scientific_properties) == 1
      assert length(enrichment.classifications) == 1
      assert length(enrichment.health_attributes) == 1
    end
  end

  describe "reconciliation safety (the key guarantee)" do
    test "enrichment survives a reconciliation pass that replaces nutrients/portions" do
      # Ensure only our row is below target so the worker processes it.
      Repo.update_all(Ingredient, set: [version: 0])
      use_fdc_client(OkStub)

      ing = ingredient_fixture(%{name: "salt", fdc_id: 999_999, data_type: nil})

      {:ok, source} =
        Food.upsert_enrichment_source(%{source_type: "doi", identifier: "10.1/salt"})

      {:ok, prop} =
        Food.create_scientific_property(%{
          ingredient_id: ing.id,
          property_key: "glycemic_index",
          value: 0.0,
          source: "literature",
          enrichment_source_id: source.id
        })

      {:ok, cls} =
        Food.create_classification(%{
          ingredient_id: ing.id,
          scientific_name: "Halite (NaCl)",
          source: "manual"
        })

      {:ok, attr} =
        Food.create_health_attribute(%{
          ingredient_id: ing.id,
          attribute: "diet:vegan",
          source: "manual"
        })

      assert :ok = perform_job(IngredientReconciliationWorker, %{})

      reloaded =
        Ingredient
        |> Repo.get!(ing.id)
        |> Repo.preload([:ingredient_portions, :ingredient_nutrients])

      # The USDA reconciliation ran: metadata corrected, child rows (re)populated.
      assert reloaded.version == IngredientReconciliationWorker.target_version()
      assert reloaded.data_type == "Foundation"
      assert length(reloaded.ingredient_portions) == 1
      assert length(reloaded.ingredient_nutrients) == 1

      # ...yet every enrichment row is byte-for-byte untouched.
      assert Repo.get!(Mehungry.Food.IngredientScientificProperty, prop.id) == prop
      assert Repo.get!(Mehungry.Food.IngredientClassification, cls.id) == cls
      assert Repo.get!(Mehungry.Food.IngredientHealthAttribute, attr.id) == attr

      enrichment = Food.list_enrichment(ing.id)
      assert [^prop] = enrichment.scientific_properties
      assert [^cls] = enrichment.classifications
      assert [^attr] = enrichment.health_attributes
    end
  end
end
