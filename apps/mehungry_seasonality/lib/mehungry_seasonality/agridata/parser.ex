defmodule MehungrySeasonality.Agridata.Parser do
  @moduledoc """
  Turns raw agri-food portal price rows into the **local-production signal**: per
  calendar month, in how many of the possible weeks a *producer-side* price was quoted.

  Only the `Farmgate price` and `Ex-packaging station price` stages count — a retail
  quote says nothing about where the product was grown. A week is identified by its
  `beginDate` and belongs to the month that date falls in; a `Month`-period row marks
  every week of that month as quoted. "Possible" weeks are the Mondays of the month,
  summed over the years that have any quote at all (so a year the country simply did
  not report does not drag every month down).
  """

  @producer_stages ["Farmgate price", "Ex-packaging station price"]

  @type result :: %{
          years: [integer()],
          months: %{optional(1..12) => %{weeks_quoted: integer(), weeks_possible: integer()}}
        }

  @spec monthly([map()]) :: result()
  def monthly(rows) do
    {weeks, full_months} =
      rows
      |> Enum.filter(&(&1["productStage"] in @producer_stages))
      |> Enum.reduce({MapSet.new(), MapSet.new()}, fn row, {weeks, full} ->
        case {row["periodType"], parse_date(row["beginDate"])} do
          {"Week", %Date{} = date} -> {MapSet.put(weeks, date), full}
          {"Month", %Date{} = date} -> {weeks, MapSet.put(full, {date.year, date.month})}
          _ -> {weeks, full}
        end
      end)

    years =
      weeks
      |> Enum.map(& &1.year)
      |> Enum.concat(Enum.map(full_months, &elem(&1, 0)))
      |> Enum.uniq()
      |> Enum.sort()

    weeks_by_month = Enum.frequencies_by(weeks, &{&1.year, &1.month})

    months =
      case years do
        [] ->
          %{}

        _ ->
          Map.new(1..12, fn month ->
            {quoted, possible} =
              Enum.reduce(years, {0, 0}, fn year, {quoted, possible} ->
                mondays = mondays_in(year, month)

                in_month =
                  if MapSet.member?(full_months, {year, month}),
                    do: mondays,
                    else: min(Map.get(weeks_by_month, {year, month}, 0), mondays)

                {quoted + in_month, possible + mondays}
              end)

            {month, %{weeks_quoted: quoted, weeks_possible: possible}}
          end)
      end

    %{years: years, months: months}
  end

  @doc """
  Per product, in how many calendar months (1–12) `rows` carry a producer-side quote
  (the rows of every product of one country, one year). Rows name only a `variety`
  (`"Peaches - Yellow flesh"`), so each is attributed to the **longest** product name
  it starts with — which keeps `"Apples for processing"` apart from `"Apples"`.
  Products with no producer-side quote are absent.
  """
  @spec months_by_product([map()], [String.t()]) :: %{String.t() => 1..12}
  def months_by_product(rows, product_names) do
    longest_first = Enum.sort_by(product_names, &String.length/1, :desc)

    rows
    |> Enum.filter(&(&1["productStage"] in @producer_stages))
    |> Enum.reduce(%{}, fn row, acc ->
      variety = row["variety"] || ""

      with %Date{month: month} <- parse_date(row["beginDate"]),
           product when is_binary(product) <-
             Enum.find(longest_first, &String.starts_with?(variety, &1)) do
        Map.update(acc, product, MapSet.new([month]), &MapSet.put(&1, month))
      else
        _ -> acc
      end
    end)
    |> Map.new(fn {product, months} -> {product, MapSet.size(months)} end)
  end

  # "DD/MM/YYYY"
  defp parse_date(<<d::binary-2, "/", m::binary-2, "/", y::binary-4>>) do
    with {day, ""} <- Integer.parse(d),
         {month, ""} <- Integer.parse(m),
         {year, ""} <- Integer.parse(y),
         {:ok, date} <- Date.new(year, month, day) do
      date
    else
      _ -> nil
    end
  end

  defp parse_date(_), do: nil

  defp mondays_in(year, month) do
    first = Date.new!(year, month, 1)

    first
    |> Date.range(Date.end_of_month(first))
    |> Enum.count(&(Date.day_of_week(&1) == 1))
  end
end
