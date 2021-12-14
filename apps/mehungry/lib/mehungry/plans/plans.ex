defmodule Mehungry.Plans do
  @moduledoc """
  The Plans context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

  alias Mehungry.Plans.MealPlan

  @doc """
  Returns the list of meal_plans.

  ## Examples

      iex> list_meal_plans()
      [%MealPlan{}, ...]

  """
  def list_meal_plans do
    Repo.all(MealPlan)
    |> Repo.preload([
      {:daily_meal_plans,
       [
         {:meals,
          [
            {:recipe,
             [
               {:recipe_ingredients, :ingredient},
               {:recipe_ingredients, :measurement_unit}
             ]}
          ]}
       ]}
    ])
  end

  @doc """
  Gets a single meal_plan.

  Raises `Ecto.NoResultsError` if the Meal plan does not exist.

  ## Examples

      iex> get_meal_plan!(123)
      %MealPlan{}

      iex> get_meal_plan!(456)
      ** (Ecto.NoResultsError)

  """
  def get_meal_plan!(id) do
    Repo.get!(MealPlan, id)
    |> Repo.preload([
      {:daily_meal_plans,
       [
         {:meals,
          [
            {:recipe,
             [
               {:recipe_ingredients, :ingredient},
               {:recipe_ingredients, :measurement_unit}
             ]}
          ]}
       ]}
    ])
  end

  @doc """
  Creates a meal_plan.

  ## Examples

      iex> create_meal_plan(%{field: value})
      {:ok, %MealPlan{}}

      iex> create_meal_plan(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_meal_plan(attrs \\ %{}) do
    %MealPlan{}
    |> MealPlan.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meal_plan.

  ## Examples

      iex> update_meal_plan(meal_plan, %{field: new_value})
      {:ok, %MealPlan{}}

      iex> update_meal_plan(meal_plan, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_meal_plan(%MealPlan{} = meal_plan, attrs) do
    meal_plan
    |> MealPlan.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a MealPlan.

  ## Examples

      iex> delete_meal_plan(meal_plan)
      {:ok, %MealPlan{}}

      iex> delete_meal_plan(meal_plan)
      {:error, %Ecto.Changeset{}}

  """
  def delete_meal_plan(%MealPlan{} = meal_plan) do
    Repo.delete(meal_plan)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking meal_plan changes.

  ## Examples

      iex> change_meal_plan(meal_plan)
      %Ecto.Changeset{source: %MealPlan{}}

  """
  def change_meal_plan(%MealPlan{} = meal_plan) do
    MealPlan.changeset(meal_plan, %{})
  end

  alias Mehungry.Plans.DailyMealPlan

  @doc """
  Returns the list of daily_meal_plans.

  ## Examples

      iex> list_daily_meal_plans()
      [%DailyMealPlan{}, ...]

  """
  def list_daily_meal_plans do
    Repo.all(DailyMealPlan)
  end

  @doc """
  Gets a single daily_meal_plan.

  Raises `Ecto.NoResultsError` if the Daily meal plan does not exist.

  ## Examples

      iex> get_daily_meal_plan!(123)
      %DailyMealPlan{}

      iex> get_daily_meal_plan!(456)
      ** (Ecto.NoResultsError)

  """
  def get_daily_meal_plan!(id), do: Repo.get!(DailyMealPlan, id)

  @doc """
  Creates a daily_meal_plan.

  ## Examples

      iex> create_daily_meal_plan(%{field: value})
      {:ok, %DailyMealPlan{}}

      iex> create_daily_meal_plan(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_daily_meal_plan(attrs \\ %{}) do
    %DailyMealPlan{}
    |> DailyMealPlan.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a daily_meal_plan.

  ## Examples

      iex> update_daily_meal_plan(daily_meal_plan, %{field: new_value})
      {:ok, %DailyMealPlan{}}

      iex> update_daily_meal_plan(daily_meal_plan, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_daily_meal_plan(%DailyMealPlan{} = daily_meal_plan, attrs) do
    daily_meal_plan
    |> DailyMealPlan.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a DailyMealPlan.

  ## Examples

      iex> delete_daily_meal_plan(daily_meal_plan)
      {:ok, %DailyMealPlan{}}

      iex> delete_daily_meal_plan(daily_meal_plan)
      {:error, %Ecto.Changeset{}}

  """
  def delete_daily_meal_plan(%DailyMealPlan{} = daily_meal_plan) do
    Repo.delete(daily_meal_plan)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking daily_meal_plan changes.

  ## Examples

      iex> change_daily_meal_plan(daily_meal_plan)
      %Ecto.Changeset{source: %DailyMealPlan{}}

  """
  def change_daily_meal_plan(%DailyMealPlan{} = daily_meal_plan) do
    DailyMealPlan.changeset(daily_meal_plan, %{})
  end

  alias Mehungry.Plans.Meal

  @doc """
  Returns the list of meals.

  ## Examples

      iex> list_meals()
      [%Meal{}, ...]

  """
  def list_meals do
    Repo.all(Meal)
  end

  @doc """
  Gets a single meal.

  Raises `Ecto.NoResultsError` if the Meal does not exist.

  ## Examples

      iex> get_meal!(123)
      %Meal{}

      iex> get_meal!(456)
      ** (Ecto.NoResultsError)

  """
  def get_meal!(id), do: Repo.get!(Meal, id)

  @doc """
  Creates a meal.

  ## Examples

      iex> create_meal(%{field: value})
      {:ok, %Meal{}}

      iex> create_meal(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_meal(attrs \\ %{}) do
    %Meal{}
    |> Meal.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a meal.

  ## Examples

      iex> update_meal(meal, %{field: new_value})
      {:ok, %Meal{}}

      iex> update_meal(meal, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_meal(%Meal{} = meal, attrs) do
    meal
    |> Meal.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a Meal.

  ## Examples

      iex> delete_meal(meal)
      {:ok, %Meal{}}

      iex> delete_meal(meal)
      {:error, %Ecto.Changeset{}}

  """
  def delete_meal(%Meal{} = meal) do
    Repo.delete(meal)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking meal changes.

  ## Examples

      iex> change_meal(meal)
      %Ecto.Changeset{source: %Meal{}}

  """
  def change_meal(%Meal{} = meal) do
    Meal.changeset(meal, %{})
  end
end
