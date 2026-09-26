defmodule MehungryWeb.Api.FoundementalFoodController do
  @moduledoc """
  Read-only JSON endpoint listing every fundamental food species with all the
  stored data for each entry.

      GET /api/foundemental_foods

  Returns `{"data": [%{id, name, variety, alternative_name, scientific_name,
  family, inserted_at, updated_at}, …]}`, name-ordered.
  """
  use MehungryWeb, :controller

  alias Mehungry.Food

  def index(conn, _params) do
    species = Food.list_foundemental_species()
    json(conn, %{data: Enum.map(species, &species_json/1)})
  end

  defp species_json(species) do
    %{
      id: species.id,
      name: species.name,
      variety: species.variety,
      alternative_name: species.alternative_name,
      scientific_name: species.scientific_name,
      family: species.family,
      inserted_at: species.inserted_at,
      updated_at: species.updated_at
    }
  end
end
