defmodule MehungryWeb.Api.V1.BasketJSON do
  @moduledoc "Serializer for the shopping basket (spec §10)."

  import MehungryWeb.Api.V1.JSON.Helpers

  def basket(basket, aisles \\ %{}) do
    items = loaded(basket.basket_items)

    data(%{
      id: basket.id,
      title: basket.title,
      updated_at: utc(basket.updated_at),
      items: Enum.map(items, &item(&1, Map.get(aisles, &1.id, "other"))),
      items_count: length(items)
    })
  end

  def item(item, aisle \\ "other") do
    mu = assoc(item.measurement_unit)

    %{
      id: item.id,
      name: item.name,
      quantity: item.quantity,
      in_storage: item.in_storage,
      measurement_unit: mu && %{id: mu.id, name: mu.name},
      recipe_id: item.recipe_id,
      usda_fdc_id: item.usda_fdc_id,
      nutrition_data: item.nutrition_data,
      aisle: aisle
    }
  end

  defp assoc(%Ecto.Association.NotLoaded{}), do: nil
  defp assoc(value), do: value

  defp loaded(list) when is_list(list), do: list
  defp loaded(_), do: []
end
