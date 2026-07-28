defmodule Mehungry.Food.CompoundMeasurementsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.CompoundMeasurement
  alias Mehungry.Literature

  setup do
    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    {:ok, study} = Literature.upsert_study(%{pmid: 30_001, title: "Oxalate content of spinach"})

    %{spinach: spinach, oxalate: oxalate, study: study}
  end

  # The worked example from the spec: Spinach / Oxalate / Raw / 750 mg/100g.
  defp raw_oxalate_attrs(spinach, oxalate, study, overrides \\ %{}) do
    Enum.into(overrides, %{
      ingredient_id: spinach.id,
      compound_id: oxalate.id,
      study_id: study.id,
      value: 750.0,
      unit: "mg/100g",
      preparation_method: "Raw",
      analytical_method: "HPLC",
      sample_size: 12,
      confidence: 0.9,
      extraction_method: "manual"
    })
  end

  describe "recording measurements" do
    test "records the Spinach/Oxalate/Raw 750 mg/100g worked example", ctx do
      {:ok, m} =
        Food.create_measurement(raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study))

      assert m.value == 750.0
      assert m.unit == "mg/100g"
      assert m.preparation_method == "Raw"
      assert m.analytical_method == "HPLC"
      assert m.sample_size == 12
      assert m.extraction_method == "manual"
      assert m.ingredient_id == ctx.spinach.id
      assert m.compound_id == ctx.oxalate.id
      assert m.study_id == ctx.study.id
    end

    test "supports all three extraction methods", ctx do
      for {method, study_pmid} <- [{"manual", 1}, {"automated", 2}, {"pdf", 3}] do
        {:ok, study} = Literature.upsert_study(%{pmid: 40_000 + study_pmid, title: "s#{study_pmid}"})

        {:ok, m} =
          Food.create_measurement(
            raw_oxalate_attrs(ctx.spinach, ctx.oxalate, study, %{extraction_method: method})
          )

        assert m.extraction_method == method
      end
    end

    test "supports manual entry with no linked study", ctx do
      {:ok, m} =
        Food.create_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{
            study_id: nil,
            extraction_method: "manual"
          })
        )

      assert m.study_id == nil
      assert m.value == 750.0
    end
  end

  describe "immutability" do
    test "re-recording the same observation is idempotent and keeps the original value", ctx do
      {:ok, first} =
        Food.record_measurement(raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study))

      # Same natural key, but a corrected/different value arrives on re-extraction.
      {:ok, second} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{value: 999.0})
        )

      assert first.id == second.id
      # The historical value is never overwritten.
      assert second.value == 750.0
      assert Food.get_measurement!(first.id).value == 750.0
      assert length(Food.list_measurements(ctx.spinach.id, ctx.oxalate.id)) == 1
    end

    test "strict create surfaces a duplicate as a changeset error", ctx do
      {:ok, _} = Food.create_measurement(raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study))

      {:error, changeset} =
        Food.create_measurement(raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study))

      refute changeset.valid?
    end

    test "a new study reporting a different value creates a new measurement", ctx do
      {:ok, older} = Literature.upsert_study(%{pmid: 30_002, title: "older"})

      {:ok, m1} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{value: 750.0})
        )

      {:ok, m2} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, older, %{value: 645.0})
        )

      refute m1.id == m2.id

      values =
        Food.list_measurements(ctx.spinach.id, ctx.oxalate.id) |> Enum.map(& &1.value) |> Enum.sort()

      assert values == [645.0, 750.0]
    end

    test "a different preparation from the same study is a distinct measurement", ctx do
      {:ok, _raw} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{
            preparation_method: "Raw",
            value: 750.0
          })
        )

      {:ok, _cooked} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{
            preparation_method: "Boiled",
            value: 470.0
          })
        )

      assert length(Food.list_measurements(ctx.spinach.id, ctx.oxalate.id)) == 2
    end
  end

  describe "validations" do
    test "value, unit, and extraction_method are required", ctx do
      {:error, changeset} =
        Food.create_measurement(%{ingredient_id: ctx.spinach.id, compound_id: ctx.oxalate.id})

      errors = errors_on(changeset)
      assert "can't be blank" in errors.value
      assert "can't be blank" in errors.unit
      assert "can't be blank" in errors.extraction_method
    end

    test "value must be non-negative", ctx do
      {:error, changeset} =
        Food.create_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{value: -1.0})
        )

      assert %{value: ["must be greater than or equal to 0"]} = errors_on(changeset)
    end

    test "sample_size must be positive", ctx do
      {:error, changeset} =
        Food.create_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{sample_size: 0})
        )

      assert %{sample_size: ["must be greater than 0"]} = errors_on(changeset)
    end

    test "confidence must be within 0.0..1.0", ctx do
      {:error, changeset} =
        Food.create_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{confidence: 1.5})
        )

      assert %{confidence: ["must be less than or equal to 1.0"]} = errors_on(changeset)
    end

    test "extraction_method must be a known value", ctx do
      {:error, changeset} =
        Food.create_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{extraction_method: "telepathy"})
        )

      assert %{extraction_method: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "read queries" do
    test "list by ingredient, compound, and study", ctx do
      {:ok, other_study} = Literature.upsert_study(%{pmid: 30_003, title: "other"})

      {:ok, _} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, ctx.study, %{preparation_method: "Raw"})
        )

      {:ok, _} =
        Food.record_measurement(
          raw_oxalate_attrs(ctx.spinach, ctx.oxalate, other_study, %{preparation_method: "Raw"})
        )

      assert length(Food.list_measurements_for_ingredient(ctx.spinach.id)) == 2
      assert length(Food.list_measurements_for_compound(ctx.oxalate.id)) == 2
      assert [%CompoundMeasurement{study_id: sid}] = Food.list_measurements_for_study(ctx.study.id)
      assert sid == ctx.study.id
    end
  end
end
