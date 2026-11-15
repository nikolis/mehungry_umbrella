defmodule MehungryWeb.ProgressOverlayChartIndexedTest do
  use ExUnit.Case, async: true

  alias MehungryWeb.ProgressOverlayChart
  alias MehungryWeb.ProgressOverlayChartIndexed, as: Chart

  defp body_history do
    [
      %{date: ~D[2026-10-01], source: :self, weight_kg: 84.0, bmi: 26.0},
      %{date: ~D[2026-10-15], source: :self, weight_kg: 82.5, bmi: nil},
      %{date: ~D[2026-11-01], source: :self, weight_kg: 81.0, bmi: 25.0}
    ]
  end

  defp nutrition_history do
    [
      %{date: ~D[2026-10-02], energy_kcal: 2100, protein_g: 95.0, carbs_g: 210.0,
        sugars_g: 40.0, fiber_g: 22.0, total_fat_g: 70.0, polyunsaturated_fat_g: 12.0,
        monounsaturated_fat_g: 25.0, trans_fat_g: 0.3},
      %{date: ~D[2026-10-05], energy_kcal: 1900, protein_g: 105.0, carbs_g: 180.0,
        sugars_g: 30.0, fiber_g: 25.0, total_fat_g: 65.0, polyunsaturated_fat_g: 10.0,
        monounsaturated_fat_g: 22.0, trans_fat_g: 0.0}
    ]
  end

  defp specs, do: ProgressOverlayChart.series_specs(body_history(), nutrition_history())

  defp svg_binary({:safe, iodata}), do: IO.iodata_to_binary(iodata)

  test "nil when nothing is selected" do
    assert Chart.overlay_svg(specs(), MapSet.new()) == nil
  end

  test "draws one path per selected series in its own color" do
    sel = MapSet.new(["weight_kg", "nutrition_protein_g", "nutrition_energy_kcal"])
    svg = svg_binary(Chart.overlay_svg(specs(), sel))

    # 3 series + the dashed 100% baseline line is a <line>, not a <path>.
    assert length(String.split(svg, "<path")) - 1 == 3

    for key <- sel do
      color = Enum.find(specs(), &(&1.key == key)).color
      assert svg =~ ~s(stroke="#{color}")
    end
  end

  test "renders a shared percentage axis with a baseline reference line" do
    svg = svg_binary(Chart.overlay_svg(specs(), MapSet.new(["weight_kg", "nutrition_energy_kcal"])))

    # Labelled %-gridlines + the rotated axis title + the 100% baseline marker.
    assert svg =~ "% of first reading"
    assert svg =~ ~r/>\d+%</
    assert svg =~ "baseline"
    # Baseline is a dashed line distinct from the series dash pattern.
    assert svg =~ ~s(stroke-dasharray="4 4")
  end

  test "nutrition series draw dashed, body series solid" do
    # body-only: no series dash (6 3); baseline (4 4) may still appear.
    body_svg = svg_binary(Chart.overlay_svg(specs(), MapSet.new(["weight_kg"])))
    refute body_svg =~ ~s(stroke-dasharray="6 3")

    # a nutrition series is dashed with the 6 3 pattern.
    nut_svg = svg_binary(Chart.overlay_svg(specs(), MapSet.new(["nutrition_protein_g"])))
    assert nut_svg =~ ~s(stroke-dasharray="6 3")
  end

  test "each point carries a <title> tooltip with its real value" do
    svg = svg_binary(Chart.overlay_svg(specs(), MapSet.new(["weight_kg"])))

    assert svg =~ "<title>"
    # Real absolute value (kg), not the normalized percentage.
    assert svg =~ "84 kg"
  end

  test "a flat series renders on the baseline without dividing by zero" do
    flat = [
      %{date: ~D[2026-10-01], source: :self, weight_kg: 80.0},
      %{date: ~D[2026-10-08], source: :self, weight_kg: 80.0}
    ]

    svg = svg_binary(Chart.overlay_svg(ProgressOverlayChart.series_specs(flat, []), MapSet.new(["weight_kg"])))
    assert svg =~ "<path"
    assert svg =~ "baseline"
  end

  test "a single-date span centers the points instead of dividing by zero" do
    same_day = [
      %{date: ~D[2026-10-01], source: :self, weight_kg: 80.0, bmi: 24.0},
      %{date: ~D[2026-10-01], source: :visit, weight_kg: 81.0, bmi: 24.2}
    ]

    svg = svg_binary(Chart.overlay_svg(ProgressOverlayChart.series_specs(same_day, []), MapSet.new(["weight_kg"])))
    assert svg =~ "<path"
  end

  test "omits a series whose first reading is non-positive (can't index from zero)" do
    zero_first = %{
      key: "nutrition_trans_fat_g", label: "Trans Fat", unit: "g",
      color: "#CE63B0", kind: :nutrition,
      points: [%{date: ~D[2026-10-01], value: 0.0}, %{date: ~D[2026-10-08], value: 2.0}]
    }

    good = %{
      key: "weight_kg", label: "Weight", unit: "kg", color: "#E8622C", kind: :body,
      points: [%{date: ~D[2026-10-01], value: 80.0}, %{date: ~D[2026-10-08], value: 78.0}]
    }

    # Only the zero-baseline series selected → nothing plottable.
    assert Chart.overlay_svg([zero_first, good], MapSet.new(["nutrition_trans_fat_g"])) == nil

    # Alongside a valid series → one path (the good one), the zero one dropped.
    svg = svg_binary(Chart.overlay_svg([zero_first, good], MapSet.new(["nutrition_trans_fat_g", "weight_kg"])))
    assert length(String.split(svg, "<path")) - 1 == 1
    assert svg =~ ~s(stroke="#E8622C")
  end
end
