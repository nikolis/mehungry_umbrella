defmodule Mehungry.SurveyFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Mehungry.Survey` context.
  """
  alias Mehungry.FoodFixtures 
  alias Mehungry.AccountsFixtures

  @doc """
  Generate a demographic.
  """
  def demographic_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()

    {:ok, demographic} =
      attrs
      |> Enum.into(%{
        capacity: "Foodie",
        year_of_birth: 1990,
        user_id: user.id
      })
      |> Mehungry.Survey.create_demographic()

    demographic
  end

  @doc """
  Generate a rating.
  """
  def rating_fixture(attrs \\ %{}) do
    user = AccountsFixtures.user_fixture()
    recipe = FoodFixtures.recipe_fixture(user)
    {:ok, rating} =
      attrs
      |> Enum.into(%{
        stars: 5,
        user_id: user.id,
        recipe_id: recipe.id
      })
      |> Mehungry.Survey.create_rating()

    rating
  end
end
