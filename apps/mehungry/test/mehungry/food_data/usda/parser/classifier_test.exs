defmodule Mehungry.FoodData.Usda.Parser.ClassifierTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.{Classifier, Result}

  defp classify(segments) do
    Classifier.classify(%Result{segments: segments}, vocabulary())
  end

  test "classifies known phrases per type" do
    result = classify([["carrot"], ["baby"], ["raw"]])

    assert [
             %{type: :food, value: "carrot", segment: 0},
             %{type: :harvest_stage, value: "baby", segment: 1},
             %{type: :processing, value: "raw", segment: 2}
           ] = result.tokens

    assert result.confidence == 1.0
  end

  test "whole-phrase match wins over word windows (longest match first)" do
    result = classify([["kosher dill"]])
    assert [%{type: :modifier, value: "kosher dill"}] = result.tokens
  end

  test "multi-word not-food alias matches" do
    result = classify([["alcoholic beverage"]])
    assert [%{type: :not_food, value: "alcoholic beverage"}] = result.tokens
  end

  test "word windows split unmatched whole phrases" do
    result = classify([["acerola juice"]])

    assert [
             %{type: :food, value: "acerola"},
             %{type: :processing, value: "juice"}
           ] = result.tokens
  end

  test "processing alias meta is carried onto the token" do
    result = classify([["pickle"]])
    assert [%{type: :processing, value: "pickled", meta: meta}] = result.tokens
    assert meta.head == true
    assert meta.implied_food == "cucumber"
  end

  test "unknown tokens penalize confidence by 0.8 each" do
    result = classify([["frobnitz"], ["blarg"]])

    assert [%{type: :unknown, value: "frobnitz"}, %{type: :unknown, value: "blarg"}] =
             result.tokens

    assert_in_delta result.confidence, 0.64, 1.0e-9
  end

  test "noise entries are dropped without penalty" do
    result = classify([["carrot"], ["nfs"]])
    assert [%{type: :food, value: "carrot"}] = result.tokens
    assert result.confidence == 1.0
  end

  test "positions are assigned in reading order" do
    result = classify([["carrot"], ["dill", "kosher dill"]])
    assert Enum.map(result.tokens, & &1.position) == [0, 1, 2]
  end
end
