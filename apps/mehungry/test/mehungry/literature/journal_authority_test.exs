defmodule Mehungry.Literature.JournalAuthorityTest do
  use ExUnit.Case, async: true

  alias Mehungry.Literature.JournalAuthority
  alias Mehungry.Literature.ScientificStudy

  describe "medline_indexed?/1" do
    test "true only for the MEDLINE status" do
      assert JournalAuthority.medline_indexed?("MEDLINE")
      assert JournalAuthority.medline_indexed?(%ScientificStudy{citation_status: "MEDLINE"})
      assert JournalAuthority.medline_indexed?(%{citation_status: "MEDLINE"})
    end

    test "false for in-pubmed-but-unindexed, blank, nil, and unknown shapes" do
      for s <- ["PubMed-not-MEDLINE", "Publisher", "In-Process", "", nil] do
        refute JournalAuthority.medline_indexed?(s)
        refute JournalAuthority.medline_indexed?(%ScientificStudy{citation_status: s})
      end

      refute JournalAuthority.medline_indexed?(%{})
      refute JournalAuthority.medline_indexed?(:nope)
    end
  end

  describe "label/1 and rank/1" do
    test "label is the badge text when indexed, nil otherwise" do
      assert JournalAuthority.label(%{citation_status: "MEDLINE"}) == "MEDLINE-indexed"
      assert JournalAuthority.label(%{citation_status: "Publisher"}) == nil
      assert JournalAuthority.label(nil) == nil
    end

    test "rank puts MEDLINE-indexed (0) before the rest (1)" do
      assert JournalAuthority.rank(%{citation_status: "MEDLINE"}) == 0
      assert JournalAuthority.rank(%{citation_status: "PubMed-not-MEDLINE"}) == 1
      assert JournalAuthority.rank(nil) == 1
    end
  end
end
