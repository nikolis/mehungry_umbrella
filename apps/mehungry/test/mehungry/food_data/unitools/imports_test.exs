defmodule Mehungry.FoodData.UniTools.ImportsTest do
  @moduledoc """
  Covers the ref-keyed review tracking: ref building, completed/skipped upsert
  (idempotent), status lookup, reviewed-ref set per dataset, counts-by-dataset,
  and reset.
  """
  use Mehungry.DataCase

  alias Mehungry.FoodData.UniTools.Imports

  test "ref/2 builds the <dataset_id>:<index> key" do
    assert Imports.ref("v1", 12) == "v1:12"
  end

  test "mark_completed/mark_skipped upsert and status_for reads back" do
    assert Imports.status_for("v1:1") == nil

    Imports.mark_skipped("v1:1")
    assert Imports.status_for("v1:1") == "skipped"

    # Re-review in place (idempotent on ref).
    Imports.mark_completed("v1:1", nil)
    assert Imports.status_for("v1:1") == "completed"
  end

  test "reviewed_refs/1 is scoped to the dataset" do
    Imports.mark_completed("v1:1", nil)
    Imports.mark_skipped("v1:2")
    Imports.mark_completed("v2:1", nil)

    refs = Imports.reviewed_refs("v1")
    assert MapSet.equal?(refs, MapSet.new(["v1:1", "v1:2"]))
  end

  test "counts_by_dataset groups completed/skipped per dataset" do
    Imports.mark_completed("v1:1", nil)
    Imports.mark_completed("v1:2", nil)
    Imports.mark_skipped("v1:3")

    assert Imports.counts_by_dataset() == %{"v1" => %{"completed" => 2, "skipped" => 1}}
  end

  test "reset clears all tracking" do
    Imports.mark_completed("v1:1", nil)
    assert Imports.reset() == 1
    assert Imports.status_for("v1:1") == nil
  end
end
