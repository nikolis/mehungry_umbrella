defmodule Mehungry.FoodData.OpenFoodFacts.ProductParserTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.OpenFoodFacts.ProductParser

  @languages MapSet.new(["en", "el", "fr"])

  defp fixture_lines do
    Path.expand("../../../fixtures/off_products_sample.jsonl", __DIR__)
    |> File.read!()
    |> String.split("\n", trim: true)
  end

  defp parse_fixture(index) do
    fixture_lines() |> Enum.at(index) |> ProductParser.parse_line(@languages)
  end

  describe "parse_line/2" do
    test "parses a European product with nutriments and translations" do
      assert {:ok, attrs, translations} = parse_fixture(0)

      assert attrs.barcode == "3017620422003"
      assert attrs.name == "Nutella"
      assert attrs.brands == "Ferrero"
      assert attrs.quantity == "400 g"
      assert "en:france" in attrs.countries
      assert "en:greece" in attrs.countries
      assert "en:spreads" in attrs.categories_tags
      assert attrs.nutriments["energy-kcal_100g"] == 539
      assert attrs.nutriments["fat_100g"] == 30.9
      # non-numeric nutriment values are dropped
      refute Map.has_key?(attrs.nutriments, "serving_size")
      assert attrs.image_url == "https://images.openfoodfacts.org/nutella.jpg"
      assert attrs.nutriscore_grade == "e"
      assert attrs.completeness == 0.9
      assert attrs.off_last_modified_t == 1_700_000_000
      assert attrs.data_source == "open_food_facts"

      langs = Enum.map(translations, & &1.language_name) |> Enum.sort()
      assert langs == ["el", "en", "fr"]

      en = Enum.find(translations, &(&1.language_name == "en"))
      assert en.name == "Nutella hazelnut spread"
      assert en.ingredients_text == "Sugar, palm oil, hazelnuts, cocoa"
    end

    test "keeps a Greek-market product with only a Greek translation" do
      assert {:ok, attrs, translations} = parse_fixture(1)
      assert attrs.barcode == "5201004013000"
      assert attrs.countries == ["en:greece"]
      assert [%{language_name: "el", name: "Φέτα ΠΟΠ"}] = translations
    end

    test "skips products not sold in Europe" do
      assert :skip = parse_fixture(2)
    end

    test "skips products without a barcode" do
      assert :skip = parse_fixture(3)
    end

    test "skips products with a non-numeric barcode" do
      assert :skip = parse_fixture(4)
    end

    test "pads a 12-digit UPC-A barcode to GTIN-13" do
      assert {:ok, attrs, _} = parse_fixture(5)
      assert attrs.barcode == "0012345678905"
    end

    test "skips products without any name" do
      assert :skip = parse_fixture(6)
    end

    test "returns an error for undecodable JSON" do
      assert {:error, _} = ProductParser.parse_line("not json at all", @languages)
    end

    test "truncates over-long string fields to 255 chars" do
      long_name = String.duplicate("a", 300)

      line =
        Jason.encode!(%{
          "code" => "4000417025999",
          "product_name" => long_name,
          "countries_tags" => ["en:germany"]
        })

      assert {:ok, attrs, _} = ProductParser.parse_line(line, @languages)
      assert String.length(attrs.name) == 255
    end

    test "matches OFF's lowercase keys for capitalized language rows" do
      line =
        Jason.encode!(%{
          "code" => "4000417025998",
          "product_name_en" => "Capitalized Language Product",
          "countries_tags" => ["en:germany"]
        })

      assert {:ok, attrs, translations} =
               ProductParser.parse_line(line, MapSet.new(["En"]))

      assert [%{language_name: "En", name: "Capitalized Language Product"}] = translations
      assert attrs.name == "Capitalized Language Product"
    end
  end

  describe "parse_api_product/2" do
    test "keeps non-European products (scanned by a user)" do
      product = %{
        "code" => "0041220576302",
        "product_name" => "American Only Snack",
        "countries_tags" => ["en:united-states"]
      }

      assert {:ok, attrs, _} = ProductParser.parse_api_product(product, @languages)
      assert attrs.barcode == "0041220576302"
    end
  end

  describe "normalize_barcode/1" do
    test "preserves leading zeros" do
      assert {:ok, "00000012345678"} = ProductParser.normalize_barcode("00000012345678")
    end

    test "pads 12 digits to 13" do
      assert {:ok, "0012345678905"} = ProductParser.normalize_barcode("012345678905")

      assert {:ok, "0123456789012"} = ProductParser.normalize_barcode("123456789012")
    end

    test "accepts EAN-8 and GTIN-14" do
      assert {:ok, "12345678"} = ProductParser.normalize_barcode("12345678")
      assert {:ok, "12345678901234"} = ProductParser.normalize_barcode("12345678901234")
    end

    test "rejects junk" do
      assert :skip = ProductParser.normalize_barcode("abc")
      assert :skip = ProductParser.normalize_barcode("1234567")
      assert :skip = ProductParser.normalize_barcode("123456789012345")
      assert :skip = ProductParser.normalize_barcode(nil)
    end
  end

  describe "european?/1" do
    test "recognizes EU members and EFTA/UK" do
      assert ProductParser.european?(["en:greece"])
      assert ProductParser.european?(["en:united-kingdom"])
      assert ProductParser.european?(["en:norway", "en:united-states"])
      refute ProductParser.european?(["en:united-states", "en:japan"])
      refute ProductParser.european?([])
    end
  end
end
