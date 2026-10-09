defmodule MehungryWeb.Api.V1.SpeciesController do
  @moduledoc """
  Foods (species) tab (spec §8). Index + detail over `FoundementalFoodSpecies`,
  enriched with bioactive-compound evidence (`Food.summarize_species/2`) and the
  conditions each implicated compound drives.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Food
  alias Mehungry.Food.EvidenceAggregation
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Health
  alias MehungryWeb.Api.Pagination
  alias MehungryWeb.Api.V1.FoodJSON

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

  def show(conn, %{"slug" => slug}) do
    case Food.get_species_by_slug(slug) do
      nil ->
        {:error, :not_found}

      species ->
        compounds = compound_evidence(species.id)
        conditions = related_conditions(compounds)
        ingredients = species_ingredients(species.id)
        json(conn, FoodJSON.species_detail(species, compounds, conditions, ingredients))
    end
  end

  defp compound_evidence(species_id) do
    species_id
    |> SpeciesCompounds.list_species_relationships()
    |> Enum.map(fn rel ->
      %{compound: rel.compound, summary: EvidenceAggregation.summarize_species(species_id, rel.compound_id)}
    end)
  end

  # Conditions implicated through the species' compounds (compound → recommendations).
  defp related_conditions(compounds) do
    compounds
    |> Enum.flat_map(fn %{compound: compound} ->
      Health.recommendations_for_compound(compound.id)
    end)
    |> Enum.uniq_by(& &1.condition_id)
    |> Enum.map(fn rec ->
      %{condition: rec.condition, recommendation: rec.recommendation, severity: rec.severity}
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
