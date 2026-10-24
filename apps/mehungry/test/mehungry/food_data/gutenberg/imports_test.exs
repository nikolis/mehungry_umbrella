defmodule Mehungry.FoodData.Gutenberg.ImportsTest do
  @moduledoc """
  Covers the ref-keyed review tracking behind the manual Gutenberg import flow:
  recording a recipe ref as completed / skipped, resuming per book
  (reviewed_refs/status_for), per-book counts, and reset.
  """
  use Mehungry.DataCase

  alias Mehungry.FoodData.Gutenberg.Imports

  test "ref/2 builds a book-scoped recipe reference" do
    assert Imports.ref("6385", 12) == "6385:12"
  end

  describe "mark_completed/2 and mark_skipped/1" do
    test "records a review outcome per ref and is idempotent" do
      ref = Imports.ref("6385", 1)
      Imports.mark_skipped(ref)
      assert Imports.status_for(ref) == "skipped"

      # Re-reviewing the same ref updates in place (no duplicate row).
      Imports.mark_completed(ref, nil)
      assert Imports.status_for(ref) == "completed"
    end

    test "unreviewed ref has no status" do
      assert Imports.status_for("6385:999") == nil
    end
  end

  describe "reviewed_refs/1" do
    test "is the set of refs acted on for that book only" do
      Imports.mark_completed("6385:1", nil)
      Imports.mark_skipped("6385:2")
      Imports.mark_completed("24407:1", nil)

      reviewed = Imports.reviewed_refs("6385")
      assert MapSet.member?(reviewed, "6385:1")
      assert MapSet.member?(reviewed, "6385:2")
      # Scoped to the book — another book's refs don't leak in.
      refute MapSet.member?(reviewed, "24407:1")
      refute MapSet.member?(reviewed, "6385:3")
    end
  end

  describe "counts_by_book/0 and reset/0" do
    test "groups outcome counts by book id; reset clears everything" do
      Imports.mark_completed("6385:1", nil)
      Imports.mark_completed("6385:2", nil)
      Imports.mark_skipped("6385:3")
      Imports.mark_completed("24407:1", nil)

      counts = Imports.counts_by_book()
      assert counts["6385"] == %{"completed" => 2, "skipped" => 1}
      assert counts["24407"] == %{"completed" => 1}

      assert Imports.reset() == 4
      assert Imports.counts_by_book() == %{}
    end
  end
end
