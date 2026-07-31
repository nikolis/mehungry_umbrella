defmodule Mehungry.Food.EvidenceAggregationTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.IngredientCompoundSummary
  alias Mehungry.Literature

  setup do
    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    %{spinach: spinach, oxalate: oxalate}
  end

  # Record one HPLC measurement, each under its own freshly-cataloged study so the
  # natural key (study_id) differs and every observation is distinct.
  defp record(ctx, value, overrides \\ %{}) do
    pmid = System.unique_integer([:positive])
    year = Map.get(overrides, :year, 2024)

    {:ok, study} =
      Literature.upsert_study(%{pmid: pmid, title: "s#{pmid}", publication_date: "#{year}"})

    attrs =
      Enum.into(overrides, %{
        ingredient_id: ctx.spinach.id,
        compound_id: ctx.oxalate.id,
        study_id: study.id,
        value: value,
        unit: "mg/100g",
        preparation_method: "Raw",
        analytical_method: "HPLC",
        sample_size: 15,
        extraction_method: "automated"
      })
      |> Map.drop([:year])

    {:ok, _} = Food.create_measurement(attrs)
  end

  describe "summarize/2 — the worked example" do
    test "Spinach / Oxalate: mean 750, range 600–900, 14 studies → :strong", ctx do
      # 14 values: mean 750, min 600, max 900, tightly clustered.
      values = [600.0, 900.0] ++ List.duplicate(750.0, 12)
      Enum.each(values, &record(ctx, &1))

      {:ok, summary} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)

      assert %IngredientCompoundSummary{} = summary
      assert summary.unit == "mg/100g"
      assert summary.mean == 750.0
      assert summary.median == 750.0
      assert summary.min == 600.0
      assert summary.max == 900.0
      assert summary.variance == 3214.29
      assert summary.study_count == 14
      assert summary.measurement_count == 14
      assert summary.total_measurement_count == 14

      # A strong, consistent, recent, HPLC-backed body of evidence.
      assert summary.evidence_level == :strong
      assert summary.evidence_score >= 0.75
      assert summary.evidence_components.study_count == 1.0
      assert summary.evidence_components.analytical_method == 1.0
      assert summary.evidence_components.consistency > 0.8
    end
  end

  describe "statistics" do
    test "computes mean, median, min, max, population variance", ctx do
      Enum.each([100.0, 200.0, 300.0], &record(ctx, &1))

      {:ok, s} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)

      assert s.mean == 200.0
      assert s.median == 200.0
      assert s.min == 100.0
      assert s.max == 300.0
      # Population variance: ((100²)+0+(100²))/3 = 6666.67; std = √ ≈ 81.65.
      assert s.variance == 6666.67
      assert s.std_dev == 81.65
    end

    test "median of an even count averages the two middle values", ctx do
      Enum.each([10.0, 20.0, 30.0, 40.0], &record(ctx, &1))

      {:ok, s} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)
      assert s.median == 25.0
    end
  end

  describe "no measurements" do
    test "returns {:error, :no_measurements} for a pair with nothing recorded", ctx do
      assert Food.summarize(ctx.spinach.id, ctx.oxalate.id) == {:error, :no_measurements}
    end
  end

  describe "evidence guardrail" do
    test "a single study is capped at :limited even with an otherwise high score", ctx do
      record(ctx, 750.0)

      {:ok, s} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)

      assert s.study_count == 1
      assert s.evidence_level == :limited
    end
  end

  describe "mixed units" do
    test "aggregates only the modal unit and flags the rest", ctx do
      Enum.each([700.0, 750.0, 800.0], &record(ctx, &1))
      # A lone measurement in a different unit must NOT be averaged in.
      record(ctx, 7.5, %{unit: "g/kg"})

      {:ok, s} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)

      assert s.unit == "mg/100g"
      assert s.mean == 750.0
      assert s.measurement_count == 3
      assert s.total_measurement_count == 4
      assert s.units_present == ["g/kg", "mg/100g"]
    end
  end

  describe "score components reflect their inputs" do
    test "estimated method and old studies lower the analytical and recency components", ctx do
      Enum.each([740.0, 760.0], fn v ->
        record(ctx, v, %{analytical_method: "Estimated", year: 2005})
      end)

      {:ok, s} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)

      assert s.evidence_components.analytical_method == 0.3
      assert s.evidence_components.recency == 0.1
      refute s.evidence_level == :strong
    end

    test "manual entries with no study drop the study-backing signal", ctx do
      # Two prep methods keep the natural key distinct with a nil study_id.
      {:ok, _} =
        Food.create_measurement(%{
          ingredient_id: ctx.spinach.id,
          compound_id: ctx.oxalate.id,
          value: 700.0,
          unit: "mg/100g",
          preparation_method: "Raw",
          analytical_method: "HPLC",
          extraction_method: "manual"
        })

      {:ok, _} =
        Food.create_measurement(%{
          ingredient_id: ctx.spinach.id,
          compound_id: ctx.oxalate.id,
          value: 800.0,
          unit: "mg/100g",
          preparation_method: "Boiled",
          analytical_method: "HPLC",
          extraction_method: "manual"
        })

      {:ok, s} = Food.summarize(ctx.spinach.id, ctx.oxalate.id)

      assert s.study_count == 0
      # No study backing (0.0) and no reported sample sizes (0.3): 0.5*0 + 0.5*0.3.
      assert s.evidence_components.publication_quality == 0.15
    end
  end

  describe "summarize_for_ingredient/1" do
    test "returns one summary per compound, ordered by compound_id", ctx do
      {:ok, lectin} = Food.upsert_compound(%{name: "Lectin", compound_type: "lectin"})

      Enum.each([700.0, 800.0], &record(ctx, &1))

      {:ok, study} =
        Literature.upsert_study(%{pmid: 99_001, title: "lectin", publication_date: "2024"})

      {:ok, _} =
        Food.create_measurement(%{
          ingredient_id: ctx.spinach.id,
          compound_id: lectin.id,
          study_id: study.id,
          value: 12.0,
          unit: "mg/100g",
          preparation_method: "Raw",
          analytical_method: "HPLC",
          extraction_method: "automated"
        })

      summaries = Food.summarize_for_ingredient(ctx.spinach.id)

      assert length(summaries) == 2
      assert Enum.map(summaries, & &1.compound_id) == Enum.sort([ctx.oxalate.id, lectin.id])

      oxalate_summary = Enum.find(summaries, &(&1.compound_id == ctx.oxalate.id))
      assert oxalate_summary.mean == 750.0
    end
  end
end
