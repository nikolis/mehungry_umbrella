defmodule Mehungry.FoodData.MyPlate.ImportsTest do
  @moduledoc """
  Covers the slug-keyed review tracking behind the manual MyPlate import flow:
  recording a slug as completed / skipped, resuming (reviewed_slugs/status_for),
  counts, and reset.
  """
  use Mehungry.DataCase

  alias Mehungry.FoodData.MyPlate.Imports

  describe "mark_completed/2 and mark_skipped/1" do
    test "records a review outcome per slug and is idempotent" do
      Imports.mark_skipped("a")
      assert Imports.status_for("a") == "skipped"

      # Re-reviewing the same slug updates in place (no duplicate row).
      Imports.mark_completed("a", nil)
      assert Imports.status_for("a") == "completed"
      assert Imports.counts() == %{"completed" => 1}
    end

    test "unreviewed slug has no status" do
      assert Imports.status_for("never-seen") == nil
    end
  end

  describe "reviewed_slugs/0" do
    test "is the set of every slug acted on (completed or skipped)" do
      Imports.mark_completed("done", nil)
      Imports.mark_skipped("passed")

      reviewed = Imports.reviewed_slugs()
      assert MapSet.member?(reviewed, "done")
      assert MapSet.member?(reviewed, "passed")
      refute MapSet.member?(reviewed, "fresh")
    end
  end

  describe "counts/0 and reset/0" do
    test "counts by status, reset clears everything" do
      Imports.mark_completed("a", nil)
      Imports.mark_completed("b", nil)
      Imports.mark_skipped("c")

      assert Imports.counts() == %{"completed" => 2, "skipped" => 1}
      assert Imports.reset() == 3
      assert Imports.counts() == %{}
    end
  end
end
