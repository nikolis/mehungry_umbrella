defmodule MehungrySeasonality.Fetcher do
  @moduledoc """
  The unit of work of a fetch: for **one species in one country**, pull both signals
  for its mapped products, store them, and re-derive the monthly statuses.

  The window is the three most recent complete calendar years. A source with no
  mapping is skipped and its stored observations cleared (the status then reads
  `unknown` for that fact). A failing API call raises so the Oban job retries.
  """

  alias MehungrySeasonality.{Agridata, Comext, Mappings, Observations, Statuses}

  @window_years 3
  @empty %{years: [], months: %{}}

  @doc """
  Fetch + store + derive. Returns `%{local: months_stored, import: months_stored}`.
  `opts[:year]` overrides "the current year" (tests).
  """
  def fetch_species(species_id, country, opts \\ []) do
    current_year = Keyword.get(opts, :year, Date.utc_today().year)
    years = Enum.to_list((current_year - @window_years)..(current_year - 1))

    by_source =
      species_id |> Mappings.for_species() |> Enum.group_by(& &1.source, & &1.external_code)

    local = fetch_local(Map.get(by_source, "agridata", []), country, years)
    imports = fetch_imports(Map.get(by_source, "comext", []), country, years)

    counts = %{
      local: Observations.replace_local(species_id, country, local),
      import: Observations.replace_imports(species_id, country, imports)
    }

    Statuses.rederive(species_id, country)
    counts
  end

  defp fetch_local([], _country, _years), do: @empty

  defp fetch_local(products, country, years) do
    products
    |> Enum.flat_map(fn product ->
      case Agridata.Client.impl().quotes(country, years, product) do
        {:ok, rows} ->
          rows

        {:error, reason} ->
          raise "agri-food portal fetch failed for #{product}: #{inspect(reason)}"
      end
    end)
    |> Agridata.Parser.monthly()
  end

  defp fetch_imports([], _country, _years), do: @empty

  defp fetch_imports(codes, country, years) do
    since = "#{List.first(years)}-01"
    until = "#{List.last(years)}-12"

    codes
    |> Enum.map(fn code ->
      case Comext.Client.impl().monthly_imports(country, code, since, until) do
        {:ok, dataset} -> dataset
        {:error, reason} -> raise "Comext fetch failed for #{code}: #{inspect(reason)}"
      end
    end)
    |> Comext.Parser.monthly()
  end
end
