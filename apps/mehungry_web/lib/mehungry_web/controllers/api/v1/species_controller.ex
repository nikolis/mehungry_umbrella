defmodule MehungryWeb.Api.V1.SpeciesController do
  @moduledoc """
  Foods (species) tab (spec §8). Index + detail over `FoundementalFoodSpecies`,
  enriched with mined biomedical research facts (`Mehungry.FactMining`), the
  per-100g nutrition of the species' curated USDA foods, and the recipes using
  them — the mobile counterpart of the web `/foods/:slug` page
  (`MehungryWeb.SpeciesDetailLive.Index`), built on the same context functions.
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.FactMining
  alias Mehungry.Food
  alias Mehungry.Food.NutrientCalculation
  alias Mehungry.Food.SpeciesNutritionSummary
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
        ingredients = species_ingredients(species.id)
        ingredient_ids = Enum.map(ingredients, & &1.id)

        # The curated top findings + the honest verdict tally — not the full fact
        # list, which runs to thousands of rows per species. The rest is reached
        # through `research/2` (search).
        curated =
          FactMining.curated_facts_for_species(species.id,
            name_term: FactMining.species_name_term(species)
          )

        research = Map.put(curated, :counts, FactMining.research_counts_for_species(species.id))
        facts = Food.promoted_species_facts_for_species(species.id, locale)

        json(
          conn,
          FoodJSON.species_detail(species, research, ingredients, facts,
            default_ingredient: SpeciesNutritionSummary.default_ingredient(ingredients),
            recipes: Food.list_sample_recipes_for_ingredients(ingredient_ids),
            recipes_count: Food.count_recipes_for_ingredients(ingredient_ids)
          )
        )
    end
  end

  @doc """
  `GET /species/:slug/research?q=` — fuzzy search over **all** of a species' mined
  facts (every label and tier), capped at 30. A blank `q` returns an empty list.
  """
  def research(conn, %{"slug" => slug} = params) do
    case Food.get_species_by_slug(slug) do
      nil ->
        {:error, :not_found}

      species ->
        results = FactMining.search_facts_for_species(species.id, params["q"])

        json(
          conn,
          data(Enum.map(results, &FoodJSON.research_fact/1), %{total: length(results)})
        )
    end
  end

  @doc """
  `GET /species/:slug/nutrition?ingredient_id=` — the per-100g nutrition of one of
  the species' curated USDA foods (the default one when `ingredient_id` is omitted):
  headline macros, the full localized nutrient tree and the summary sentences.
  404 when the ingredient is not curated onto the species (or it has none).
  """
  def nutrition(conn, %{"slug" => slug} = params) do
    with %{} = species <- Food.get_species_by_slug(slug),
         ingredients = species_ingredients(species.id),
         %{id: ingredient_id} <- pick_ingredient(ingredients, params["ingredient_id"]) do
      ingredient = Food.get_ingredient_details!(ingredient_id)
      tree = NutrientCalculation.ingredient_nutrient_tree(ingredient, 100)

      json(
        conn,
        FoodJSON.species_nutrition(species, ingredient, tree, Locale.resolve(conn, params))
      )
    else
      _ -> {:error, :not_found}
    end
  end

  defp pick_ingredient(ingredients, nil),
    do: SpeciesNutritionSummary.default_ingredient(ingredients)

  defp pick_ingredient(ingredients, ""), do: pick_ingredient(ingredients, nil)

  defp pick_ingredient(ingredients, id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> Enum.find(ingredients, &(&1.id == int))
      _ -> nil
    end
  end

  defp pick_ingredient(_ingredients, _id), do: nil

  defp species_ingredients(species_id) do
    species_id
    |> Food.get_species_with_ingredients!()
    |> SpeciesNutritionSummary.species_ingredients()
  end
end
