defmodule Mehungry.InventoryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Inventory` context.
  """

  @doc """
  Generate a shoping_basket.
  """
  def shoping_basket_fixture(attrs \\ %{}) do
    {:ok, shoping_basket} =
      attrs
      |> Enum.into(%{
        end_dt: ~N[2023-01-25 11:01:00],
        start_dt: ~N[2023-01-25 11:01:00]
      })
      |> Mehungry.Inventory.create_shoping_basket()

    shoping_basket
  end

  @doc """
  Generate a ingredient_basket.
  """
  def ingredient_basket_fixture(attrs \\ %{}) do
    {:ok, ingredient_basket} =
      attrs
      |> Enum.into(%{
        quantity: 120.5
      })
      |> Mehungry.Inventory.create_ingredient_basket()

    ingredient_basket
  end
end
