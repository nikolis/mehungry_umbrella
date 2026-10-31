defmodule Mehungry.Literature.ResearchTypeTest do
  use ExUnit.Case, async: true

  alias Mehungry.Literature.ResearchType

  describe "bucket/1" do
    test "maps the strongest designs to the systematic-review bucket" do
      assert ResearchType.bucket("systematic_review") == :systematic_review
      assert ResearchType.bucket("meta_analysis") == :systematic_review
    end

    test "folds randomized and controlled trials together" do
      assert ResearchType.bucket("randomized_controlled_trial") == :controlled_trial
      assert ResearchType.bucket("controlled_trial") == :controlled_trial
    end

    test "maps the observational designs" do
      assert ResearchType.bucket("cohort") == :cohort
      assert ResearchType.bucket("case_control") == :case_control
      assert ResearchType.bucket("cross_sectional") == :cross_sectional
    end

    test "groups case reports/series and guidelines/reviews" do
      assert ResearchType.bucket("case_report") == :case_report
      assert ResearchType.bucket("case_series") == :case_report
      assert ResearchType.bucket("guideline") == :guideline_review
      assert ResearchType.bucket("review") == :guideline_review
    end

    test "sinks preclinical and low-signal types into preclinical_other" do
      for d <- ~w(editorial letter animal in_vitro) do
        assert ResearchType.bucket(d) == :preclinical_other
      end
    end

    test "unknown / nil / unmapped fall to :unknown, never guessed" do
      assert ResearchType.bucket("unknown") == :unknown
      assert ResearchType.bucket(nil) == :unknown
      assert ResearchType.bucket("") == :unknown
      assert ResearchType.bucket("something_new") == :unknown
    end
  end

  describe "ordering and labels" do
    test "buckets are in strict ascending display order" do
      orders = Enum.map(ResearchType.buckets(), fn {_k, _l, o} -> o end)
      assert orders == Enum.sort(orders)
      assert Enum.uniq(orders) == orders
    end

    test "every bucket key has a label and order, and :unknown sorts last" do
      for {key, label, order} <- ResearchType.buckets() do
        assert ResearchType.label(key) == label
        assert ResearchType.order(key) == order
      end

      last = ResearchType.buckets() |> List.last() |> elem(0)
      assert last == :unknown
    end
  end
end
