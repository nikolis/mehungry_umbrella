defmodule Mehungry.FoodData.Usda.Parser.PipelineTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.{Pipeline, Result, Skipped}

  defp parse(text, opts \\ []) do
    Pipeline.parse(text, Keyword.put_new(opts, :vocabulary, vocabulary()))
  end

  describe "golden inputs" do
    test "Carrots, baby, raw" do
      assert {:ok,
              %Result{
                canonical_food: "carrot",
                canonical_food_id: 1,
                harvest_stage: :baby,
                processing: [:raw],
                processing_modifiers: [],
                packaging: :na,
                confidence: 1.0
              }} = parse("Carrots, baby, raw")
    end

    test "Pickles, cucumber, dill or kosher dill" do
      assert {:ok,
              %Result{
                canonical_food: "cucumber",
                canonical_food_id: 2,
                harvest_stage: :mature,
                processing: [:pickled],
                processing_modifiers: ["dill", "kosher dill"],
                packaging: :na,
                confidence: 1.0
              }} = parse("Pickles, cucumber, dill or kosher dill")
    end

    test "Oil, corn" do
      assert {:ok, %Result{canonical_food: "corn", processing: [:oil], confidence: 1.0}} =
               parse("Oil, corn")
    end

    test "Tomato, puree, canned" do
      assert {:ok,
              %Result{
                canonical_food: "tomato",
                processing: [:puree],
                packaging: :canned,
                confidence: 1.0
              }} = parse("Tomato, puree, canned")
    end

    test "Acerola juice, raw" do
      assert {:ok,
              %Result{canonical_food: "acerola", processing: [:juice, :raw], confidence: 1.0}} =
               parse("Acerola juice, raw")
    end

    test "Alcoholic beverage, wine, table, red is skipped" do
      assert {:skipped, %Skipped{reason: :not_food, text: "Alcoholic beverage, wine, table, red"}} =
               parse("Alcoholic beverage, wine, table, red")
    end

    test "Spinach, frozen, chopped or leaf" do
      assert {:ok,
              %Result{
                canonical_food: "spinach",
                processing: [:frozen],
                processing_modifiers: ["chopped", "leaf"],
                confidence: 1.0
              }} = parse("Spinach, frozen, chopped or leaf")
    end

    test "Beef, loin, T-bone steak, raw" do
      assert {:ok,
              %Result{
                canonical_food: "beef",
                part: "loin",
                dismemberment: "t bone steak",
                processing: [:raw],
                confidence: 1.0
              }} = parse("Beef, loin, T-bone steak, raw")
    end

    test "full beef cut: part, dismemberment, bone_state, portion, grade, fat" do
      assert {:ok,
              %Result{
                canonical_food: "beef",
                part: "loin",
                dismemberment: "top loin steak",
                bone_state: "boneless",
                portion: ["separable lean only"],
                grade: "choice",
                fat: "trimmed to 1/8 fat",
                processing: [:raw]
              }} =
               parse(
                 "Beef, loin, top loin steak, boneless, lip-on, separable lean only, trimmed to 1/8\" fat, choice, raw"
               )
    end

    test "Chicken breast, meat only, boneless, skinless, raw" do
      assert {:ok,
              %Result{
                canonical_food: "chicken breast",
                bone_state: "boneless",
                portion: ["meat only", "skinless"],
                processing: [:raw],
                confidence: 1.0
              }} = parse("Chicken breast, meat only, boneless, skinless, raw")
    end

    test "Milk, whole, 3.25% milkfat, with added vitamin D" do
      assert {:ok, %Result{canonical_food: "milk", fat: "3.25% milkfat"}} =
               parse("Milk, whole, 3.25% milkfat, with added vitamin D")
    end

    test "Beef, ground, 85% lean 15% fat, raw" do
      assert {:ok, %Result{canonical_food: "beef", fat: "85% lean 15% fat", processing: [:raw]}} =
               parse("Beef, ground, 85% lean 15% fat, raw")
    end

    test "White bread, commercial is skipped as a prepared dish" do
      assert {:skipped, %Skipped{reason: :prepared_dish, text: "White bread, commercial"}} =
               parse("White bread, commercial")
    end

    test "Chestnuts, european, roasted" do
      assert {:ok,
              %Result{
                canonical_food: "chestnut",
                processing: [:roasted],
                processing_modifiers: ["european"],
                confidence: 1.0
              }} = parse("Chestnuts, european, roasted")
    end
  end

  describe "confidence degradation" do
    test "bare Pickles uses the implied food at 0.9" do
      assert {:ok, %Result{canonical_food: "cucumber", confidence: 0.9}} = parse("Pickles")
    end

    test "unknown head food falls back to free text (0.8 unknown × 0.5 fallback)" do
      assert {:ok,
              %Result{
                canonical_food: "frobnitz",
                canonical_food_id: nil,
                packaging: :canned,
                confidence: 0.4
              }} = parse("Frobnitz, canned")
    end

    test "unknown qualifier degrades to a modifier at 0.8" do
      assert {:ok,
              %Result{
                canonical_food: "carrot",
                processing_modifiers: ["shredded"],
                confidence: 0.8
              }} = parse("Carrots, shredded")
    end
  end

  describe "tracing" do
    test "off by default" do
      assert {:ok, %Result{trace: nil}} = parse("Oil, corn")
    end

    test "records every stage when enabled" do
      assert {:ok, %Result{trace: trace}} = parse("Oil, corn", trace: true)
      stages = Enum.map(trace, & &1.stage)
      assert :tokenizer in stages
      assert :normalizer in stages
      assert :classifier in stages
      assert :rule in stages
    end

    test "skipped results keep their trace" do
      assert {:skipped, %Skipped{trace: [_ | _]}} =
               parse("Alcoholic beverage, daiquiri, canned", trace: true)
    end
  end

  test "ambiguous input is deterministic" do
    {:ok, first} = parse("Pickles, cucumber, dill or kosher dill")
    {:ok, second} = parse("Pickles, cucumber, dill or kosher dill")
    assert first == second
  end

  test "version/0 returns a semver string" do
    assert Pipeline.version() =~ ~r/^\d+\.\d+\.\d+$/
  end
end
