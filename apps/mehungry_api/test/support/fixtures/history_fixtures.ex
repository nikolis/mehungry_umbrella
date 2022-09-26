defmodule MehungryApi.HistoryFixtures do
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
        meal_datetime: ~U[2022-02-13 16:50:00Z],
        title: "some title"
      })
      |> MehungryApi.History.create_user_meal()

    user_meal
  end
end
