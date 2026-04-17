defmodule MehungryWeb.Professional.IngredientLive.Show do
  use MehungryWeb, :live_view

  alias Mehungry.Food

  def mount(%{"id" => id}, _session, socket) do
    ingredient =
      Food.get_ingredient!(id)
      |> Mehungry.Repo.preload([
        :category,
        :measurement_unit,
        ingredient_portions: [:measurement_unit],
        ingredient_nutrients: [nutrient: :measurement_unit],
        ingredient_translation: [:language]
      ])

    {:ok, assign(socket, :ingredient, ingredient)}
  end
end
