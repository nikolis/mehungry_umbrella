defmodule MehungrySeasonality.Comext.Parser do
  @moduledoc """
  Turns Comext JSON-stat datasets into the **import signal**: per calendar month, the
  average tonnes imported and the top origin countries with their share.

  JSON-stat stores observations in a flat `value` map keyed by a row-major index over
  the dimensions listed in `id` with the sizes in `size`; each dimension's
  `category.index` maps a code to its position. Quantities arrive in 100 kg.

  Several datasets (one per mapped product code) are summed. The monthly total is the
  `WORLD` partner; origins are the individual 2-letter partner countries (aggregates
  like `EXT_EU` and Comext's `Q*` pseudo-countries are dropped). The average is over
  the years that have any data.
  """

  @top_origins 5
  @min_share 0.01

  @type result :: %{
          years: [integer()],
          months: %{optional(1..12) => %{tonnes_avg: float(), origins: [map()]}}
        }

  @spec monthly([map()]) :: result()
  def monthly(datasets) do
    # %{{partner, year, month} => quantity in 100 kg}, summed across datasets
    cells =
      Enum.reduce(datasets, %{}, fn dataset, acc ->
        Map.merge(acc, cells(dataset), fn _key, a, b -> a + b end)
      end)

    years =
      cells
      |> Enum.filter(fn {{partner, _y, _m}, qty} -> partner == "WORLD" and qty > 0 end)
      |> Enum.map(fn {{_p, year, _m}, _} -> year end)
      |> Enum.uniq()
      |> Enum.sort()

    months =
      case years do
        [] -> %{}
        _ -> Map.new(1..12, fn month -> {month, month_summary(cells, month, length(years))} end)
      end

    %{years: years, months: months}
  end

  defp month_summary(cells, month, n_years) do
    by_partner =
      cells
      |> Enum.filter(fn {{_p, _y, m}, _} -> m == month end)
      |> Enum.group_by(fn {{partner, _y, _m}, _} -> partner end, fn {_k, qty} -> qty end)
      |> Map.new(fn {partner, quantities} -> {partner, Enum.sum(quantities)} end)

    world = Map.get(by_partner, "WORLD", 0)

    origins =
      if world > 0 do
        by_partner
        |> Enum.filter(fn {partner, _} -> origin_country?(partner) end)
        |> Enum.map(fn {partner, qty} -> %{"country" => partner, "share" => qty / world} end)
        |> Enum.filter(&(&1["share"] >= @min_share))
        |> Enum.sort_by(& &1["share"], :desc)
        |> Enum.take(@top_origins)
        |> Enum.map(&Map.update!(&1, "share", fn share -> Float.round(share, 2) end))
      else
        []
      end

    # 100 kg → tonnes, averaged over the years in the window
    %{tonnes_avg: Float.round(world / 10 / n_years, 1), origins: origins}
  end

  # Individual countries are plain 2-letter codes; Comext's `Q*` codes are
  # pseudo-countries (stores and provisions, confidential, not specified).
  defp origin_country?(<<a, b>>) when a in ?A..?Z and b in ?A..?Z, do: a != ?Q
  defp origin_country?(_), do: false

  defp cells(%{"id" => ids, "size" => sizes, "value" => value, "dimension" => dims}) do
    partner_at = position_lookup(dims, "partner")
    time_at = position_lookup(dims, "time")
    partner_dim = Enum.find_index(ids, &(&1 == "partner"))
    time_dim = Enum.find_index(ids, &(&1 == "time"))

    value
    |> entries()
    |> Enum.reduce(%{}, fn {index, qty}, acc ->
      coords = coordinates(index, sizes)

      with true <- is_number(qty),
           partner when is_binary(partner) <- partner_at[Enum.at(coords, partner_dim)],
           {year, month} <- parse_period(time_at[Enum.at(coords, time_dim)]) do
        Map.update(acc, {partner, year, month}, qty, &(&1 + qty))
      else
        _ -> acc
      end
    end)
  end

  defp cells(_), do: %{}

  # `value` is a sparse object keyed by stringified index, or (rarely) a dense array.
  defp entries(value) when is_map(value) do
    Enum.map(value, fn {index, qty} -> {String.to_integer(index), qty} end)
  end

  defp entries(value) when is_list(value) do
    value |> Enum.with_index() |> Enum.map(fn {qty, index} -> {index, qty} end)
  end

  defp position_lookup(dims, name) do
    dims
    |> get_in([name, "category", "index"])
    |> Kernel.||(%{})
    |> Map.new(fn {code, position} -> {position, code} end)
  end

  # Row-major flat index → one coordinate per dimension.
  defp coordinates(index, sizes) do
    {coords, _} =
      sizes
      |> Enum.reverse()
      |> Enum.reduce({[], index}, fn size, {coords, rest} ->
        {[rem(rest, size) | coords], div(rest, size)}
      end)

    coords
  end

  defp parse_period(<<y::binary-4, "-", m::binary-2>>) do
    with {year, ""} <- Integer.parse(y), {month, ""} <- Integer.parse(m) do
      {year, month}
    else
      _ -> nil
    end
  end

  defp parse_period(_), do: nil
end
