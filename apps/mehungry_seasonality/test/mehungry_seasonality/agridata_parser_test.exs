defmodule MehungrySeasonality.Agridata.ParserTest do
  use ExUnit.Case, async: true

  alias MehungrySeasonality.Agridata.Parser

  @fixture Path.expand("../fixtures/agridata_el_peaches_2024.json", __DIR__)

  defp row(stage, period_type, begin_date) do
    %{"productStage" => stage, "periodType" => period_type, "beginDate" => begin_date}
  end

  test "recorded Greek peach quotes show a May–October season" do
    result = @fixture |> File.read!() |> Jason.decode!() |> Parser.monthly()

    assert result.years == [2024]
    assert result.months[1].weeks_quoted == 0
    assert result.months[3].weeks_quoted == 0
    assert result.months[7].weeks_quoted >= 3
    assert result.months[8].weeks_quoted >= 3
    assert result.months[12].weeks_quoted == 0
    # July 2024 has five Mondays
    assert result.months[7].weeks_possible == 5
  end

  test "only producer-side stages count" do
    rows = [
      row("Retail buying price", "Week", "01/07/2024"),
      row("Retail selling price", "Week", "08/07/2024")
    ]

    assert Parser.monthly(rows) == %{years: [], months: %{}}
  end

  test "the same week quoted at two stages or varieties counts once" do
    rows = [
      row("Farmgate price", "Week", "01/07/2024"),
      row("Ex-packaging station price", "Week", "01/07/2024"),
      row("Ex-packaging station price", "Week", "08/07/2024")
    ]

    assert Parser.monthly(rows).months[7] == %{weeks_quoted: 2, weeks_possible: 5}
  end

  test "a Month-period row marks every week of that month as quoted" do
    rows = [row("Farmgate price", "Month", "01/06/2024")]

    # June 2024 has four Mondays
    assert Parser.monthly(rows).months[6] == %{weeks_quoted: 4, weeks_possible: 4}
  end

  test "possible weeks sum only over years that have any quote" do
    rows = [
      row("Farmgate price", "Week", "03/07/2023"),
      row("Farmgate price", "Week", "01/07/2024")
    ]

    result = Parser.monthly(rows)
    assert result.years == [2023, 2024]
    # July 2023 and July 2024 each have five Mondays
    assert result.months[7] == %{weeks_quoted: 2, weeks_possible: 10}
  end

  test "malformed rows are ignored" do
    rows = [row("Farmgate price", "Week", "not a date"), row("Farmgate price", "Year", nil)]
    assert Parser.monthly(rows) == %{years: [], months: %{}}
  end
end
