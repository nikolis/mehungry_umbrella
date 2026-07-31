defmodule Mehungry.FoodData.Usda.Parser.NormalizerTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Usda.Parser.Normalizer

  describe "normalize/1" do
    test "downcases, strips punctuation, collapses whitespace" do
      assert Normalizer.normalize("  Kosher-Dill! ") == "kosher dill"
    end

    test "singularizes only the last word of a phrase" do
      assert Normalizer.normalize("Baby Carrots") == "baby carrot"
    end

    test "plural normalization examples" do
      assert Normalizer.normalize("Carrots") == "carrot"
      assert Normalizer.normalize("Tomatoes") == "tomato"
      assert Normalizer.normalize("Pickles") == "pickle"
      assert Normalizer.normalize("Berries") == "berry"
      assert Normalizer.normalize("Leaves") == "leaf"
      assert Normalizer.normalize("Radishes") == "radish"
      assert Normalizer.normalize("Peaches") == "peach"
    end

    test "empty and whitespace-only input" do
      assert Normalizer.normalize("   ") == ""
    end

    test "preserves %, . and / so fat numerics survive" do
      assert Normalizer.normalize("3.25% milkfat") == "3.25% milkfat"
      assert Normalizer.normalize("85% lean 15% fat") == "85% lean 15% fat"
      # the inch mark is dropped, the fraction kept
      assert Normalizer.normalize("trimmed to 1/8\" fat") == "trimmed to 1/8 fat"
    end
  end

  describe "singularize/1" do
    test "irregulars" do
      assert Normalizer.singularize("leaves") == "leaf"
      assert Normalizer.singularize("halves") == "half"
    end

    test "keep-list words stay singular" do
      assert Normalizer.singularize("hummus") == "hummus"
      assert Normalizer.singularize("couscous") == "couscous"
    end

    test "'ss' endings are kept" do
      assert Normalizer.singularize("molasses") == "molasses"
      assert Normalizer.singularize("watercress") == "watercress"
    end

    test "sibilant '-es' plurals drop 'es', not just 's'" do
      assert Normalizer.singularize("radishes") == "radish"
      assert Normalizer.singularize("peaches") == "peach"
      assert Normalizer.singularize("boxes") == "box"
      assert Normalizer.singularize("dishes") == "dish"
    end

    test "single letters and non-plurals are untouched" do
      assert Normalizer.singularize("s") == "s"
      assert Normalizer.singularize("corn") == "corn"
    end
  end
end
