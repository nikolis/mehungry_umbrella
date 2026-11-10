defmodule Mehungry.FoodData.Faostat.Client do
  @moduledoc """
  Loads FAOSTAT "Production: Crops and livestock products" (QCL) rows from the CSV
  bundled under the `:mehungry` app's `priv/faostat/` directory
  (see `docs/implementation/science/species_enrichment.md`).

  Bundled (not fetched) — offline-safe and deterministic, mirroring the UniTools/MyPlate
  importers — and parsed once and cached for a day. FAOSTAT data is **CC BY 4.0**;
  attribution is rendered wherever producers surface. Behind
  `Mehungry.FoodData.Faostat.ClientBehaviour` (`:faostat_client` key) so tests stub it.
  """

  @behaviour Mehungry.FoodData.Faostat.ClientBehaviour

  alias NimbleCSV.RFC4180, as: CSV

  @cache :recipes_cache
  @cache_key {:faostat, :production_rows}
  @cache_ttl :timer.hours(24)
  @path "faostat/production.csv"

  @doc "The configured client module (this module in prod, a stub in tests)."
  def impl, do: Application.get_env(:mehungry, :faostat_client, __MODULE__)

  @impl true
  def load_rows do
    case cache_get(@cache_key) do
      {:ok, rows} when is_list(rows) ->
        {:ok, rows}

      _ ->
        with {:ok, body} <- File.read(file_path()) do
          rows = parse_csv(body)
          cache_put(@cache_key, rows)
          {:ok, rows}
        end
    end
  end

  defp parse_csv(body) do
    body
    |> CSV.parse_string()
    |> Enum.flat_map(fn
      [item_code, item, area, year, value] ->
        with {year_int, _} <- Integer.parse(String.trim(year)),
             {tonnes, _} <- Float.parse(String.trim(value)) do
          [
            %{
              item_code: String.trim(item_code),
              item: String.trim(item),
              area: String.trim(area),
              year: year_int,
              value_tonnes: tonnes
            }
          ]
        else
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp file_path, do: Path.join(:code.priv_dir(:mehungry), @path)

  defp cache_get(key) do
    case Cachex.get(@cache, key) do
      {:ok, nil} -> :error
      {:ok, value} -> {:ok, value}
      _ -> :error
    end
  end

  defp cache_put(key, value), do: Cachex.put(@cache, key, value, ttl: @cache_ttl)
end
