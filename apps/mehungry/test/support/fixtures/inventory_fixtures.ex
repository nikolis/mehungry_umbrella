defmodule Mehungry.InventoryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Inventory` context.
  """

  @doc """
  Generate a shopping_basket.
  """
  def shopping_basket_fixture(attrs \\ %{}) do
    shopping_basket =
      attrs
      |> Enum.into(%{
        title: "test tittle",
        end_dt: ~N[2023-01-25 11:01:00],
        start_dt: ~N[2023-01-25 11:01:00],
        basket_ingredients: []
      })
      |> Mehungry.Inventory.create_shopping_basket()

    shopping_basket
  end

  @doc """
  Generate a basket_ingredient.
  """
  def basket_ingredient_fixture(attrs \\ %{}) do
    {:ok, basket_ingredient} =
      attrs
      |> Enum.into(%{
        quantity: 120.5
      })
      |> Mehungry.Inventory.create_basket_ingredient()

    basket_ingredient
  end
end
