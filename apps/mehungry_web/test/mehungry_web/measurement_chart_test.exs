defmodule MehungryWeb.MeasurementChartTest do
  @moduledoc """
  Unit tests for the KPI-card math of the shared progress dashboard
  (`MehungryWeb.MeasurementChart`). Pure functions — no DB.
  """
  use ExUnit.Case, async: true

  alias MehungryWeb.MeasurementChart

  describe "cards/1 delta tone" do
    test "an unchanged float metric reads as :flat, not :bad" do
      # Float deltas arrive as 0.0 — a literal integer `0` pattern would miss
      # them and tint flat progress red (regression test).
      history = [
        %{date: ~D[2026-01-01], source: :visit, weight_kg: 80.0},
        %{date: ~D[2026-02-01], source: :visit, weight_kg: 80.0}
      ]

      assert [%{key: "weight_kg", tone: :flat, arrow: "–"}] = MeasurementChart.cards(history)
    end

    test "a drop in weight reads as :good, a rise as :bad" do
      down = [
        %{date: ~D[2026-01-01], source: :visit, weight_kg: 82.0},
        %{date: ~D[2026-02-01], source: :visit, weight_kg: 80.5}
      ]

      up = [
        %{date: ~D[2026-01-01], source: :visit, weight_kg: 80.5},
        %{date: ~D[2026-02-01], source: :visit, weight_kg: 82.0}
      ]

      assert [%{tone: :good, arrow: "▼"}] = MeasurementChart.cards(down)
      assert [%{tone: :bad, arrow: "▲"}] = MeasurementChart.cards(up)
    end

    test "BMR is never judged — tone stays :flat either way" do
      history = [
        %{date: ~D[2026-01-01], source: :visit, bmr_kcal: 1400},
        %{date: ~D[2026-02-01], source: :visit, bmr_kcal: 1500}
      ]

      assert [%{key: "bmr_kcal", tone: :flat, arrow: "▲"}] = MeasurementChart.cards(history)
    end
  end
end
