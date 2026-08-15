defmodule Mehungry.AI.Agents.RecipeAgentProvenanceTest do
  use ExUnit.Case, async: true

  alias Mehungry.AI.Agents.RecipeAgent

  # These guard the 🔴 ingredient-ID resolution bug: submit_recipe must reject any
  # ingredient_id that was never returned by search_ingredient/create_ingredient
  # this run, or whose id disagrees with the name the model claims for it.
  # `offered` mirrors what the agent accumulates in its process dictionary
  # (id => the candidate name we handed back).

  describe "check_provenance/3" do
    # Pecorino Romano was offered as 100, black pepper as 200.
    @offered %{100 => "Cheese, pecorino romano", 200 => "Spices, pepper, black"}

    test "accepts an id that was offered and whose name agrees" do
      assert RecipeAgent.check_provenance(100, "Pecorino Romano", @offered) == []
    end

    test "rejects a hallucinated id that was never offered (the Domino's case)" do
      # 9999 is a real-but-wrong row (e.g. a Branded 'DOMINO'S Pizza') that search
      # never returns, so it is absent from the offered map.
      [error] = RecipeAgent.check_provenance(9999, "Pecorino Romano", @offered)
      assert error =~ "was never returned by search_ingredient"
      assert error =~ "9999"
    end

    test "rejects two offered ids swapped between ingredients" do
      # Model submits the black-pepper id (200) but claims it is the cheese.
      [error] = RecipeAgent.check_provenance(200, "Pecorino Romano", @offered)
      assert error =~ ~s(is "Spices, pepper, black", not "Pecorino Romano")
    end

    test "a blank name still passes the id gate but skips the name gate" do
      assert RecipeAgent.check_provenance(100, nil, @offered) == []
      assert [_ | _] = RecipeAgent.check_provenance(9999, nil, @offered)
    end
  end

  describe "name_matches?/2" do
    test "matches legitimate USDA-style name variants without thrash" do
      assert RecipeAgent.name_matches?("pecorino", "Cheese, pecorino romano")
      assert RecipeAgent.name_matches?("black pepper", "Spices, pepper, black")
      assert RecipeAgent.name_matches?("olive oil", "Oil, olive, salad or cooking")
    end

    test "rejects a gross mismatch" do
      refute RecipeAgent.name_matches?("black pepper", "Cheese, pecorino romano")
      refute RecipeAgent.name_matches?("bay leaf", "Tea, black, brewed")
    end
  end
end
