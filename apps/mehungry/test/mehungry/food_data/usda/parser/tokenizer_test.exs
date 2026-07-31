defmodule Mehungry.FoodData.Usda.Parser.TokenizerTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Usda.Parser.Tokenizer

  test "splits on commas into segments" do
    assert Tokenizer.tokenize("Carrots, baby, raw") == [["Carrots"], ["baby"], ["raw"]]
  end

  test "splits alternatives on ' or ' within a segment" do
    assert Tokenizer.tokenize("Pickles, cucumber, dill or kosher dill") ==
             [["Pickles"], ["cucumber"], ["dill", "kosher dill"]]
  end

  test "splits alternatives on ';'" do
    assert Tokenizer.tokenize("Spinach, chopped; frozen") ==
             [["Spinach"], ["chopped", "frozen"]]
  end

  test "does NOT split on ' and ' — it binds single qualifier concepts" do
    assert Tokenizer.tokenize("Beef, separable lean and fat, raw") ==
             [["Beef"], ["separable lean and fat"], ["raw"]]

    assert Tokenizer.tokenize("Chicken, wing, meat and skin") ==
             [["Chicken"], ["wing"], ["meat and skin"]]
  end

  test "splits accompaniments on ' with '" do
    assert Tokenizer.tokenize("Zucchini, raw with skin") == [["Zucchini"], ["raw", "skin"]]
  end

  test "lifts parentheticals into sibling phrases of the same segment" do
    assert Tokenizer.tokenize("Coriander (cilantro) leaves, raw") ==
             [["Coriander leaves", "cilantro"], ["raw"]]
  end

  test "ignores empty segments and stray whitespace" do
    assert Tokenizer.tokenize("  Oil ,  , corn  ") == [["Oil"], ["corn"]]
  end

  test "does not split words merely containing 'or'" do
    assert Tokenizer.tokenize("Corn, oriental") == [["Corn"], ["oriental"]]
  end
end
