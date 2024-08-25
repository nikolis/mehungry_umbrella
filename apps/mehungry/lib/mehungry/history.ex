defmodule Mehungry.History do
  @moduledoc """
  The History context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.History.ConsumeRecipeUserMeal
  alias Mehungry.History
  alias Mehungry.Repo

  alias Mehungry.History.UserMeal

  @doc """
  Returns the list of history_user_meals.

  ## Examples

      iex> list_history_user_meals()
      [%UserMeal{}, ...]

  """
  def list_history_user_meals do
    Repo.all(UserMeal)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  alias History.RecipeUserMeal

  def get_available_portions_for_user_meal(recipe_user_meal_id) do
    result =
      from(cum in ConsumeRecipeUserMeal,
        join: rum in RecipeUserMeal,
        on: rum.id == ^recipe_user_meal_id,
        where: cum.user_meal_id == rum.user_meal_id
      )
      |> Repo.aggregate(:sum, :consume_portions)

    recipe_user_meal =
      from(rum in RecipeUserMeal, where: rum.id == ^recipe_user_meal_id)
      |> Repo.one()

    result =
      case result do
        nil ->
          0

        anything_else ->
          anything_else
      end

    recipe_user_meal.cooking_portions - (result + recipe_user_meal.consume_portions)
  end

  # TODO use the date_time to only show incomplete meals to show user warning
  def list_incomplete_user_meals2(user_id, _date_time) do
    query =
      from rum in RecipeUserMeal,
        join: um in UserMeal,
        on: um.id == rum.user_meal_id,
        left_join: cum in ConsumeRecipeUserMeal,
        on: cum.user_meal_id == um.id,
        where: um.user_id == ^user_id and rum.cooking_portions > rum.consume_portions,
        having:
          (is_nil(cum.consume_portions) and rum.consume_portions < rum.cooking_portions) or
            sum(cum.consume_portions) + rum.consume_portions < rum.cooking_portions,
        group_by: [cum.id, rum.id, um.id]

    Repo.all(query)
    |> Repo.preload([:user_meal, :recipe])
  end

  def list_history_user_meals_for_user(user_id) do
    query =
      from meal in UserMeal,
        where: meal.user_id == ^user_id

    Repo.all(query)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  def list_history_user_meals_for_user(user_id, date) do
    {:ok, date} = NaiveDateTime.from_iso8601(date <> " 00:00:00")

    query =
      from meal in UserMeal,
        where: meal.user_id == ^user_id and meal.start_dt == ^date

    Repo.all(query)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  def list_history_user_meals_for_user(user_id, start_dt, end_dt) do
    end_dt = NaiveDateTime.add(end_dt, 24, :hour)

    query =
      from meal in UserMeal,
        where:
          meal.user_id == ^user_id and ^start_dt <= meal.start_dt and
            (^end_dt >= meal.end_dt or is_nil(meal.end_dt))

    Repo.all(query)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  @doc """
  Gets a single user_meal.

  Raises `Ecto.NoResultsError` if the User meal does not exist.

  ## Examples

      iex> get_user_meal!(123)
      %UserMeal{}

      iex> get_user_meal!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user_meal!(id) do
    Repo.get!(UserMeal, id)
    |> Repo.preload(
      recipe_user_meals: [
        recipe: [
          recipe_ingredients: [
            :measurement_unit,
            ingredient: [:category, :ingredient_translation]
          ]
        ]
      ]
    )
  end

  def get_user_meal_raw!(id) do
    Repo.get!(UserMeal, id)
    |> Repo.preload(
      consume_recipe_user_meals: [recipe_user_meal: :recipe],
      recipe_user_meals: [
        :recipe
      ]
    )
  end

  @doc """
  Creates a user_meal.

  ## Examples

      iex> create_user_meal(%{field: value})
      {:ok, %UserMeal{}}

      iex> create_user_meal(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user_meal(attrs \\ %{}) do
    %UserMeal{}
    |> UserMeal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_meal.

  ## Examples

      iex> update_user_meal(user_meal, %{field: new_value})
      {:ok, %UserMeal{}}

      iex> update_user_meal(user_meal, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_meal(%UserMeal{} = user_meal, attrs) do
    user_meal
    |> UserMeal.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_meal.

  ## Examples

      iex> delete_user_meal(user_meal)
      {:ok, %UserMeal{}}

      iex> delete_user_meal(user_meal)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user_meal(%UserMeal{} = user_meal) do
    Repo.delete(user_meal)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_meal changes.

  ## Examples

      iex> change_user_meal(user_meal)
      %Ecto.Changeset{data: %UserMeal{}}

  """
  def change_user_meal(%UserMeal{} = user_meal, attrs \\ %{}) do
    UserMeal.changeset(user_meal, attrs)
  end
end
