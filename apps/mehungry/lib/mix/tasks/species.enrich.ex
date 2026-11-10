defmodule Mix.Tasks.Species.Enrich do
  @shortdoc "Fetch Wikidata + FAOSTAT enrichment facts for species (review-gated)"

  @moduledoc """
  Populates the species-enrichment review queue (see
  `docs/implementation/science/species_enrichment.md`). For each
  `FoundementalFoodSpecies` it fetches:

    * **Wikidata** (CC0) — origin region, short description (en/el), Wikipedia link.
    * **FAOSTAT** (CC BY 4.0) — top producing countries (only when the species has a
      curated `faostat_item_code`; run `mix species.faostat_crosswalk` first).

  Everything lands as a **pending** `SpeciesFact` — nothing surfaces until an admin
  promotes it at `/professional/species-enrichment`.

      mix species.enrich                       # all species, both sources
      mix species.enrich --source wikidata     # Wikidata only
      mix species.enrich --source faostat      # FAOSTAT only
      mix species.enrich --only Apple          # one species by name/slug

  Options:

    * `--source` — `all` (default) | `wikidata` | `faostat`
    * `--only`   — restrict to one species (name or slug, hyphens → spaces)
  """

  use Mix.Task

  alias Mehungry.Food
  alias Mehungry.FoodData.Faostat
  alias Mehungry.FoodData.Wikidata

  @requirements ["app.start"]
  # Be polite to the Wikidata API between species.
  @wikidata_pause_ms 250

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [source: :string, only: :string])
    source = opts[:source] || "all"
    species = target_species(opts[:only])

    Mix.shell().info("Enriching #{length(species)} species (source: #{source})\n")

    faostat_rows = if source in ["all", "faostat"], do: load_faostat(), else: []

    totals =
      Enum.reduce(species, %{wikidata: 0, faostat: 0}, fn sp, acc ->
        wd = if source in ["all", "wikidata"], do: enrich_wikidata(sp), else: 0
        fa = if source in ["all", "faostat"], do: enrich_faostat(sp, faostat_rows), else: 0
        Mix.shell().info("  #{sp.name}: #{wd} Wikidata + #{fa} FAOSTAT")
        %{wikidata: acc.wikidata + wd, faostat: acc.faostat + fa}
      end)

    Mix.shell().info(
      "\nDone — #{totals.wikidata} Wikidata + #{totals.faostat} FAOSTAT facts queued. " <>
        "Review at /professional/species-enrichment."
    )
  end

  defp target_species(nil), do: Food.list_foundemental_species()

  defp target_species(only) do
    name = String.replace(only, "-", " ")

    Food.list_foundemental_species()
    |> Enum.filter(&(String.downcase(&1.name) == String.downcase(name)))
    |> case do
      [] -> Mix.raise("No species matching #{inspect(only)}")
      list -> list
    end
  end

  defp enrich_wikidata(sp) do
    {:ok, result} = Wikidata.Client.impl().fetch(sp.name, sp.scientific_name)
    count = Food.record_species_wikidata_facts(sp.id, result)
    Process.sleep(@wikidata_pause_ms)
    count
  end

  defp enrich_faostat(%{faostat_item_code: nil}, _rows), do: 0

  defp enrich_faostat(%{faostat_item_code: code} = sp, rows) do
    producers = Faostat.Parser.top_producers(rows, code)
    Food.record_species_faostat_facts(sp.id, producers)
  end

  defp load_faostat do
    case Faostat.Client.impl().load_rows() do
      {:ok, rows} -> rows
      _ -> []
    end
  end
end
