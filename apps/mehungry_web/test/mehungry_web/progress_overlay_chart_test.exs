defmodule MehungryWeb.ProgressOverlayChartTest do
  use ExUnit.Case, async: true

  alias MehungryWeb.ProgressOverlayChart, as: Chart

  defp body_history do
    [
      %{date: ~D[2026-10-01], source: :self, weight_kg: 84.0, bmi: 26.0},
      %{date: ~D[2026-10-15], source: :self, weight_kg: 82.5, bmi: nil},
      %{date: ~D[2026-11-01], source: :self, weight_kg: 81.0, bmi: 25.0}
    ]
  end

  defp nutrition_history do
    [
      %{
        date: ~D[2026-10-02],
        energy_kcal: 2100,
        protein_g: 95.0,
        carbs_g: 210.0,
        sugars_g: 40.0,
        fiber_g: 22.0,
        total_fat_g: 70.0,
        polyunsaturated_fat_g: 12.0,
        monounsaturated_fat_g: 25.0,
        trans_fat_g: 0.3
      },
      %{
        date: ~D[2026-10-05],
        energy_kcal: 1900,
        protein_g: 105.0,
        carbs_g: 180.0,
        sugars_g: 30.0,
        fiber_g: 25.0,
        total_fat_g: 65.0,
        polyunsaturated_fat_g: 10.0,
        monounsaturated_fat_g: 22.0,
        trans_fat_g: 0.0
      }
    ]
  end

  describe "series_specs/2" do
    test "includes only series with at least two points, body first" do
      specs = Chart.series_specs(body_history(), nutrition_history())
      keys = Enum.map(specs, & &1.key)

      # bmi has 2 points (Oct 1 + Nov 1); nil point dropped. All 9 nutrition
      # series have 2 rows each.
      assert "weight_kg" in keys
      assert "bmi" in keys
      refute "waist_cm" in keys
      assert "nutrition_energy_kcal" in keys
      assert length(keys) == 2 + 9

      # Body series come before nutrition series.
      assert Enum.take_while(specs, &(&1.kind == :body)) |> length() == 2
    end

    test "specs carry latest value with unit and a stable color" do
      specs = Chart.series_specs(body_history(), nutrition_history())
      weight = Enum.find(specs, &(&1.key == "weight_kg"))
      energy = Enum.find(specs, &(&1.key == "nutrition_energy_kcal"))

      assert weight.latest == "81 kg"
      assert energy.latest == "1900 kcal"
      assert weight.color != energy.color

      # Color is keyed to the series, not to what else is available.
      [only_energy] = Chart.series_specs([], nutrition_history()) |> Enum.filter(&(&1.key == "nutrition_energy_kcal"))
      assert only_energy.color == energy.color
    end
  end

  describe "sanitize_selection/2" do
    test "defaults to the first body series on first load (nil)" do
      specs = Chart.series_specs(body_history(), nutrition_history())
      assert Chart.sanitize_selection(nil, specs) == MapSet.new(["weight_kg"])
    end

    test "prunes stale keys and keeps valid ones" do
      specs = Chart.series_specs(body_history(), nutrition_history())
      sel = MapSet.new(["weight_kg", "waist_cm", "bogus"])

      assert Chart.sanitize_selection(sel, specs) == MapSet.new(["weight_kg"])
    end

    test "an empty selection re-defaults on reload (deselect-all only lasts within the session)" do
      specs = Chart.series_specs(body_history(), nutrition_history())
      assert Chart.sanitize_selection(MapSet.new(), specs) == MapSet.new(["weight_kg"])
    end

    test "stays empty when there is nothing chartable" do
      assert Chart.sanitize_selection(MapSet.new(["weight_kg"]), []) == MapSet.new()
      assert Chart.sanitize_selection(nil, []) == MapSet.new()
    end

    test "falls back to the first nutrition series when no body series exists" do
      specs = Chart.series_specs([], nutrition_history())
      assert Chart.sanitize_selection(nil, specs) == MapSet.new(["nutrition_total_fat_g"])
    end
  end

  describe "axis/2" do
    test "is the union date range of the selected series only" do
      specs = Chart.series_specs(body_history(), nutrition_history())

      assert Chart.axis(specs, MapSet.new(["weight_kg"])) == {~D[2026-10-01], ~D[2026-11-01]}

      assert Chart.axis(specs, MapSet.new(["nutrition_protein_g"])) ==
               {~D[2026-10-02], ~D[2026-10-05]}

      assert Chart.axis(specs, MapSet.new(["weight_kg", "nutrition_protein_g"])) ==
               {~D[2026-10-01], ~D[2026-11-01]}

      assert Chart.axis(specs, MapSet.new()) == nil
    end
  end

  describe "legend_entries/2" do
    test "one entry per selected series with label, color and latest value" do
      specs = Chart.series_specs(body_history(), nutrition_history())
      sel = MapSet.new(["weight_kg", "nutrition_energy_kcal"])

      legend = Chart.legend_entries(specs, sel)

      assert Enum.map(legend, & &1.key) == ["weight_kg", "nutrition_energy_kcal"]
      assert Enum.find(legend, &(&1.key == "nutrition_energy_kcal")).latest == "1900 kcal"
      assert Enum.all?(legend, &String.starts_with?(&1.color, "#"))
    end
  end
end
