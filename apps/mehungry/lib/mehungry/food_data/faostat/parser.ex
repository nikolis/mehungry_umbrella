defmodule Mehungry.FoodData.Faostat.Parser do
  @moduledoc """
  Pure selection over FAOSTAT production rows (see `Faostat.Client`). Picks the latest
  year's top-N producing countries for a given FAOSTAT item code.
  """

  @doc """
  Top-`limit` producing countries for `item_code`, by production tonnage in the latest
  year present. Returns `[%{country: "China", tonnes: 47571100.0, year: 2022}, ...]`
  (ranked, descending). Empty when the item has no rows.
  """
  def top_producers(rows, item_code, limit \\ 3)
      when is_list(rows) and is_binary(item_code) do
    item_rows = Enum.filter(rows, &(&1.item_code == item_code))

    case item_rows do
      [] ->
        []

      rows ->
        latest = rows |> Enum.map(& &1.year) |> Enum.max()

        rows
        |> Enum.filter(&(&1.year == latest))
        |> Enum.sort_by(& &1.value_tonnes, :desc)
        |> Enum.take(limit)
        |> Enum.map(&%{country: &1.area, tonnes: &1.value_tonnes, year: &1.year})
    end
  end

  @doc "The distinct `{item_code, item}` pairs present in the rows — for the crosswalk helper."
  def items(rows) when is_list(rows) do
    rows
    |> Enum.map(&{&1.item_code, &1.item})
    |> Enum.uniq()
    |> Enum.sort_by(fn {_code, item} -> item end)
  end
end
