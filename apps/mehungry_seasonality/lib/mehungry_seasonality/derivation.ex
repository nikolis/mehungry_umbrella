defmodule MehungrySeasonality.Derivation do
  @moduledoc """
  Pure rules turning the raw observations of one species × country into the twelve
  monthly statuses. No database access — everything here is a function of its inputs.

  **Local** (from the share of weeks with a producer price quote):

    * no local source mapped → `unknown` for every month;
    * quoted in at least half of the possible weeks → on the market that month;
    * on the market in **all twelve** months → `unresolved` for every month: the
      product is greenhouse-grown or stored for part of the year and price quotes
      cannot say which months — an admin decides;
    * otherwise on-the-market months are `in_season`, the rest `none`.

  **Imported** (from average monthly tonnes):

    * no import source mapped → `unknown`;
    * below the tonnage floor → `none`;
    * at least half of that product's own peak month → `major`, else `some`.

  Local and imported are independent: a month can be both `in_season` and `major`.
  """

  # Share of possible weeks with a producer quote for the month to count as "on the market".
  @local_share 0.5
  # Average tonnes in a month below which imports are treated as noise.
  @import_floor_tonnes 10.0
  # Fraction of the product's peak import month from which a month is "major".
  @import_major_share 0.5

  @type derived :: %{month: 1..12, local: String.t(), imported: String.t(), top_origins: [map()]}

  @doc """
  Derive twelve months. `local` / `imports` are `%{month => observation}` maps (structs
  or maps with the observation fields); pass `nil` when that source is not mapped.
  """
  @spec derive(map() | nil, map() | nil) :: [derived()]
  def derive(local, imports) do
    local_by_month = derive_local(local)
    imported_by_month = derive_imported(imports)

    Enum.map(1..12, fn month ->
      {imported, origins} = Map.fetch!(imported_by_month, month)

      %{
        month: month,
        local: Map.fetch!(local_by_month, month),
        imported: imported,
        top_origins: origins
      }
    end)
  end

  defp derive_local(nil), do: Map.new(1..12, &{&1, "unknown"})

  defp derive_local(observations) do
    on_market = Map.new(1..12, fn month -> {month, on_market?(observations[month])} end)

    if Enum.all?(on_market, fn {_month, on?} -> on? end) do
      Map.new(1..12, &{&1, "unresolved"})
    else
      Map.new(on_market, fn {month, on?} -> {month, if(on?, do: "in_season", else: "none")} end)
    end
  end

  defp on_market?(%{weeks_quoted: quoted, weeks_possible: possible}) when possible > 0,
    do: quoted / possible >= @local_share

  defp on_market?(_), do: false

  defp derive_imported(nil), do: Map.new(1..12, &{&1, {"unknown", []}})

  defp derive_imported(observations) do
    tonnes = Map.new(1..12, fn month -> {month, tonnes(observations[month])} end)
    peak = tonnes |> Map.values() |> Enum.max()

    Map.new(1..12, fn month ->
      t = tonnes[month]

      cond do
        t < @import_floor_tonnes -> {month, {"none", []}}
        t >= peak * @import_major_share -> {month, {"major", origins(observations[month])}}
        true -> {month, {"some", origins(observations[month])}}
      end
    end)
  end

  defp tonnes(%{tonnes_avg: tonnes}) when is_number(tonnes), do: tonnes
  defp tonnes(_), do: 0.0

  defp origins(%{origins: origins}) when is_list(origins), do: origins
  defp origins(_), do: []
end
