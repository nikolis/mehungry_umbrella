defmodule MehungrySeasonality.Comext.ParserTest do
  use ExUnit.Case, async: true

  alias MehungrySeasonality.Comext.Parser

  @fixture Path.expand("../fixtures/comext_gr_0702_2024.json", __DIR__)

  # A minimal JSON-stat dataset: partners × two months, quantities in 100 kg.
  defp dataset(cells, times \\ ["2024-01", "2024-02"]) do
    partners = cells |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    value =
      for {partner, time, qty} <- cells, into: %{} do
        index =
          Enum.find_index(partners, &(&1 == partner)) * length(times) +
            Enum.find_index(times, &(&1 == time))

        {Integer.to_string(index), qty}
      end

    %{
      "id" => ["partner", "time"],
      "size" => [length(partners), length(times)],
      "value" => value,
      "dimension" => %{
        "partner" => %{"category" => %{"index" => index_map(partners)}},
        "time" => %{"category" => %{"index" => index_map(times)}}
      }
    }
  end

  defp index_map(codes), do: codes |> Enum.with_index() |> Map.new()

  test "recorded Greek tomato imports peak in September with Turkey as top origin" do
    result = @fixture |> File.read!() |> Jason.decode!() |> List.wrap() |> Parser.monthly()

    assert result.years == [2024]

    {peak_month, _} = Enum.max_by(result.months, fn {_month, m} -> m.tonnes_avg end)
    assert peak_month == 9
    assert_in_delta result.months[9].tonnes_avg, 8661, 5

    assert [%{"country" => "TR", "share" => share} | _] = result.months[9].origins
    assert share > 0.5
  end

  test "aggregates and pseudo-countries are never origins" do
    result =
      Parser.monthly([
        dataset([
          {"WORLD", "2024-01", 1000},
          {"EXT_EU", "2024-01", 600},
          {"INT_EU27_2020", "2024-01", 400},
          {"QP", "2024-01", 50},
          {"TR", "2024-01", 600},
          {"NL", "2024-01", 350}
        ])
      ])

    assert result.months[1].tonnes_avg == 100.0

    assert result.months[1].origins == [
             %{"country" => "TR", "share" => 0.6},
             %{"country" => "NL", "share" => 0.35}
           ]
  end

  test "several product codes are summed" do
    a = dataset([{"WORLD", "2024-01", 1000}, {"TR", "2024-01", 1000}])
    b = dataset([{"WORLD", "2024-01", 3000}, {"NL", "2024-01", 3000}])

    result = Parser.monthly([a, b])

    assert result.months[1].tonnes_avg == 400.0

    assert [%{"country" => "NL", "share" => 0.75}, %{"country" => "TR", "share" => 0.25}] =
             result.months[1].origins
  end

  test "the monthly figure is averaged over the years with data" do
    result =
      Parser.monthly([
        dataset(
          [{"WORLD", "2023-03", 1000}, {"WORLD", "2024-03", 3000}],
          ["2023-03", "2024-03"]
        )
      ])

    assert result.years == [2023, 2024]
    assert result.months[3].tonnes_avg == 200.0
    assert result.months[4].tonnes_avg == 0.0
  end

  test "no data yields an empty result" do
    assert Parser.monthly([]) == %{years: [], months: %{}}
    assert Parser.monthly([dataset([])]) == %{years: [], months: %{}}
  end
end
