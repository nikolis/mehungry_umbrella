defmodule MehungryWeb.Api.V1.SpeciesController do
  @moduledoc """
  Foods (species) tab (spec §8). Index + detail over `FoundementalFoodSpecies`,
  enriched with bioactive-compound evidence (`Food.summarize_species/2`).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Food
  alias Mehungry.Food.EvidenceAggregation
  alias Mehungry.Food.SpeciesCompounds
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.FoodJSON
  alias MehungryWeb.Api.V1.Locale

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, params) do
    species =
      case params["q"] do
        q when is_binary(q) and q != "" -> Food.search_species(q)
        _ -> Food.list_foundemental_species()
      end

    {page, meta} = Pagination.paginate_list(species, Pagination.params(params))
    meta = Map.put(meta, :total, length(species))
    json(conn, data(Enum.map(page, &FoodJSON.species_summary/1), meta))
  end

  def show(conn, %{"slug" => slug} = params) do
    case Food.get_species_by_slug(slug) do
      nil ->
        {:error, :not_found}

      species ->
        compounds = compound_evidence(species.id, Locale.resolve(conn, params))
        ingredients = species_ingredients(species.id)
        json(conn, FoodJSON.species_detail(species, compounds, ingredients))
    end
  end

  # Overlays each compound's translated name (from the curated `compound_translations`,
  # with English fallback) so the mobile Foods tab matches the web species page's
  # Bioactive Compounds section.
  defp compound_evidence(species_id, locale) do
    rels = SpeciesCompounds.list_species_relationships(species_id)
    names = Food.compound_display_names(Enum.map(rels, & &1.compound.id), locale)

    Enum.map(rels, fn rel ->
      compound =
        case Map.get(names, rel.compound.id) do
          nil -> rel.compound
          translated -> %{rel.compound | name: translated}
        end

      %{compound: compound, summary: EvidenceAggregation.summarize_species(species_id, rel.compound_id)}
    end)
  end

  defp species_ingredients(species_id) do
    species_id
    |> Food.get_species_with_ingredients!()
    |> Map.get(:foundemental_foods, [])
    |> Enum.map(& &1.ingredient)
    |> Enum.reject(&is_nil/1)
  end
end
