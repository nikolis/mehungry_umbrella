defmodule MehungryWeb.Api.V1.SpeciesController do
  @moduledoc """
  Foods (species) tab (spec §8). Index + detail over `FoundementalFoodSpecies`,
  enriched with mined biomedical research facts (`Mehungry.FactMining`).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.FactMining
  alias Mehungry.Food
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.FoodJSON
  alias MehungryWeb.Api.V1.Locale

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, params) do
    # Public scope only — species an admin marked private are hidden from the app
    # (the admin curation view uses the non-public variants).
    species =
      case params["q"] do
        q when is_binary(q) and q != "" -> Food.search_public_species(q)
        _ -> Food.list_public_foundemental_species()
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
        locale = Locale.resolve(conn, params)
        research = FactMining.list_facts_for_species(species.id)
        ingredients = species_ingredients(species.id)
        facts = Food.promoted_species_facts_for_species(species.id, locale)
        json(conn, FoodJSON.species_detail(species, research, ingredients, facts))
    end
  end

  defp species_ingredients(species_id) do
    species_id
    |> Food.get_species_with_ingredients!()
    |> Map.get(:foundemental_foods, [])
    |> Enum.map(& &1.ingredient)
    |> Enum.reject(&is_nil/1)
  end
end
