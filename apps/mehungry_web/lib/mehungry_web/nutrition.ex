defmodule MehungryWeb.Nutrition do
  @moduledoc """
  Public API for nutrition-related operations.
  """

  alias MehungryWeb.NutrientMapper

  @doc """
  Get a human-readable nutrient name by USDA ID
  """
  def nutrient_name(nutrient_id, fallback_name \\ nil) do
    NutrientMapper.get_nutrient_name(nutrient_id, fallback_name)
  end

  @doc """
  Get all nutrient mappings
  """
  def all_nutrients do
    NutrientMapper.get_all_mappings()
  end

  @doc """
  Check if the nutrient mapper is ready
  """
  def ready? do
    case NutrientMapper.status() do
      %{loaded_count: count} when count > 0 -> true
      _ -> false
    end
  end
end
