defmodule MehungryWeb.Api.V1.ConditionController do
  @moduledoc """
  Conditions tab (spec §8). List + detail with dietary guidance (compound
  recommendations) and the implicated species (`Health.species_for_condition/2`).
  """
  use MehungryWeb, :controller

  import MehungryWeb.Api.V1.JSON.Helpers

  alias Mehungry.Health
  alias MehungryWeb.Api.V1.FoodJSON

  action_fallback MehungryWeb.Api.V1.FallbackController

  def index(conn, _params) do
    conditions = Health.list_conditions()
    json(conn, data(Enum.map(conditions, &FoodJSON.condition_summary/1)))
  end

  def show(conn, %{"id" => id}) do
    with {:ok, condition} <- fetch_condition(id) do
      recommendations = Health.recommendations_for_condition(condition.id)
      species = Health.species_for_condition(condition.id)
      json(conn, FoodJSON.condition_detail(condition, recommendations, species))
    end
  end

  @doc "GET /api/v1/conditions/:id/species/:species_id — the food-for-condition drill-in."
  def species(conn, %{"id" => id, "species_id" => species_id}) do
    with {:ok, condition} <- fetch_condition(id) do
      sid = String.to_integer(species_id)

      row =
        condition.id
        |> Health.species_for_condition()
        |> Enum.find(&(&1.species.id == sid))

      case row do
        nil -> {:error, :not_found}
        row -> json(conn, data(species_row(condition, row)))
      end
    end
  end

  defp species_row(condition, %{species: species} = row) do
    %{
      condition: %{id: condition.id, name: condition.name},
      species: FoodJSON.species_summary(species),
      compound: row.compound && row.compound.name,
      recommendation: row.recommendation,
      severity: row.severity,
      evidence_level: row.evidence_level
    }
  end

  defp fetch_condition(id) do
    {:ok, Health.get_condition!(String.to_integer(to_string(id)))}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    ArgumentError -> {:error, :not_found}
  end
end
