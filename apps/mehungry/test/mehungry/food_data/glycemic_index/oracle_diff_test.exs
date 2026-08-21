defmodule Mehungry.FoodData.GlycemicIndex.OracleDiffTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.GlycemicIndex.OracleDiff

  defp oracle(food, gi, unpublished \\ false),
    do: %{food_item: food, gi_value: gi, unpublished: unpublished}

  test "buckets agree / diverge / uncovered and skips unpublished rows" do
    oracle_rows = [
      oracle("Apples, raw", 38.0),
      # matches Banana species but our value is far off → diverge
      oracle("Bananas, ripe", 51.0),
      # no species with a value → uncovered
      oracle("Dragonfruit, fresh", 40.0),
      # unpublished → expected gap, excluded from publishable
      oracle("Secret cake", 60.0, true)
    ]

    rederived = [
      %{name: "Apple", values: [40.0, 36.0]},
      %{name: "Banana", values: [72.0]}
    ]

    r = OracleDiff.compare(oracle_rows, rederived, tolerance: 10.0)

    assert r.total_oracle == 4
    assert r.unpublished == 1
    assert r.publishable == 3
    assert r.agree == 1
    assert r.diverge == 1
    assert r.uncovered == 1
    assert r.covered == 2

    # coverage = covered / publishable ; agreement = agree / covered
    assert r.coverage_pct == Float.round(2 * 100 / 3, 1)
    assert r.agreement_pct == 50.0

    assert [%{species: "Banana", oracle_gi: 51.0, our_gi: 72.0, delta: 21.0}] = r.divergences
  end

  test "picks the nearest re-derived value when a species has several" do
    r =
      OracleDiff.compare(
        [oracle("Rice, boiled", 64.0)],
        [%{name: "Rice", values: [90.0, 66.0, 50.0]}],
        tolerance: 5.0
      )

    assert r.agree == 1
    assert r.divergences == []
  end

  test "flags orphan species that matched no publishable oracle row" do
    r =
      OracleDiff.compare(
        [oracle("Apples, raw", 38.0)],
        [%{name: "Apple", values: [38.0]}, %{name: "Rambutan", values: [59.0]}]
      )

    assert r.orphan_species == ["Rambutan"]
  end

  test "tolerance controls the agree/diverge boundary" do
    rows = [oracle("Apple", 38.0)]
    rederived = [%{name: "Apple", values: [46.0]}]

    assert OracleDiff.compare(rows, rederived, tolerance: 5.0).diverge == 1
    assert OracleDiff.compare(rows, rederived, tolerance: 10.0).agree == 1
  end
end
