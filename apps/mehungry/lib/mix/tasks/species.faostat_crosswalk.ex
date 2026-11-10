defmodule Mix.Tasks.Species.FaostatCrosswalk do
  @shortdoc "Suggest FAOSTAT item codes for species missing a crosswalk"

  @moduledoc """
  Fuzzy-matches each `FoundementalFoodSpecies` name against the bundled FAOSTAT item
  list (`priv/faostat/production.csv`) and prints a suggested `faostat_item_code` with a
  confidence score, so an admin can confirm the crosswalk into the species (via the USDA
  Schema editor / a console update). Read-only — it never writes.

      mix species.faostat_crosswalk                 # all species missing a code
      mix species.faostat_crosswalk --all           # include species that already have one
      mix species.faostat_crosswalk --threshold 0.8 # only show matches at/above this score

  FAOSTAT names are crop-level, so this is a curation aid, not an automatic mapping.
  See `docs/implementation/science/species_enrichment.md`.
  """

  use Mix.Task

  alias Mehungry.Food
  alias Mehungry.FoodData.Faostat.{Client, Parser}

  @requirements ["app.start"]

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [all: :boolean, threshold: :float])

    threshold = opts[:threshold] || 0.82
    {:ok, rows} = Client.impl().load_rows()
    items = Parser.items(rows)

    species =
      Food.list_foundemental_species()
      |> then(fn all ->
        if opts[:all], do: all, else: Enum.filter(all, &is_nil(&1.faostat_item_code))
      end)

    Mix.shell().info("FAOSTAT items available: #{length(items)}")
    Mix.shell().info("Species to match: #{length(species)}\n")

    Enum.each(species, fn sp ->
      case best_match(sp.name, items) do
        {code, item, score} when score >= threshold ->
          Mix.shell().info(
            "#{pad(sp.name)} → #{code}  #{item}  (#{Float.round(score, 2)})#{current(sp)}"
          )

        _ ->
          :ok
      end
    end)

    Mix.shell().info("\nConfirm a match by setting `faostat_item_code` on the species.")
  end

  defp best_match(name, items) do
    down = String.downcase(name)

    items
    |> Enum.map(fn {code, item} -> {code, item, String.jaro_distance(down, String.downcase(item))} end)
    |> Enum.max_by(fn {_c, _i, score} -> score end, fn -> nil end)
  end

  defp current(%{faostat_item_code: nil}), do: ""
  defp current(%{faostat_item_code: code}), do: "  [current: #{code}]"

  defp pad(name), do: String.pad_trailing(name, 28)
end
