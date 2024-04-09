defmodule Mehungry.HistoryFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `MehungryApi.History` context.
  """

  @doc """
  Generate a user_meal.
  """
  def user_meal_fixture(attrs \\ %{}) do
    {:ok, user_meal} =
      attrs
      |> Enum.into(%{
        start_dt: ~U[2022-02-13 16:50:00Z],
        end_dt: ~U[2022-02-13 18:50:00Z],
        recipe_user_meals: [],
        title: "some title"
      })
      |> Mehungry.History.create_user_meal()

    user_meal
  end
end
