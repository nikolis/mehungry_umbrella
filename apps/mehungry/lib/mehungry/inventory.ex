defmodule Mehungry.Inventory do
  @moduledoc """
  The Inventory context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo
  alias Mehungry.Inventory.BasketItem
  alias Mehungry.Inventory.BasketParams

  def change_basket_params(%BasketParams{} = basket_params, attrs \\ %{}) do
    BasketParams.changeset(basket_params, attrs)
  end

  alias Mehungry.Inventory.ShoppingBasket

  @doc """
  Returns the list of shopping_baskets.

  ## Examples

      iex> list_shopping_baskets()
      [%ShoppingBasket{}, ...]

  """
  def list_shopping_baskets do
    Repo.all(ShoppingBasket)
  end

  def list_shopping_baskets_for_user(user_id) do
    from(s in ShoppingBasket,
      where: s.user_id == ^user_id
    )
    |> Repo.all()
    |> Repo.preload(
      basket_items: [
        :measurement_unit
      ],
      basket_ingredients: [
        :measurement_unit,
        ingredient: [
          :category,
          :ingredient_translation
        ]
      ]
    )
  end

  @doc """
  Gets a single shopping_basket.

  Raises `Ecto.NoResultsError` if the Shoping basket does not exist.

  ## Examples

      iex> get_shopping_basket!(123)
      %ShoppingBasket{}

      iex> get_shopping_basket!(456)
      ** (Ecto.NoResultsError)

  """
  def get_shopping_basket!(id) do
    Repo.get!(ShoppingBasket, id)
    |> Repo.preload(
      basket_items: [
        :measurement_unit
      ],
      basket_ingredients: [
        :measurement_unit,
        ingredient: [
          :category,
          :ingredient_translation
        ]
      ]
    )
  end

  @doc """
  Creates a shopping_basket.

  ## Examples

      iex> create_shopping_basket(%{field: value})
      {:ok, %ShoppingBasket{}}

      iex> create_shopping_basket(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs) do
    result =
      shopping_basket
      |> ShoppingBasket.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, basket} ->
        basket =
          basket
          |> Repo.preload(
            basket_ingredients: [
              :measurement_unit,
              ingredient: [
                :category,
                :ingredient_translation
              ]
            ]
          )

        {:ok, basket}

      _ ->
        result
    end
  end

  def add_item(basket_id, item_params) do
    basket = get_shopping_basket!(basket_id)

    result =
      %BasketItem{}
      |> BasketItem.changeset(%{
        list_id: basket.id,
        name: item_params.name,
        quantity: item_params.quantity,
        shopping_basket_id: basket_id,
        measurement_unit_id: item_params.measurement_unit_id,
        nutrition_data: item_params.nutrition,
        usda_fdc_id: item_params.usda_fdc_id,
        checked: false
      })
      |> Repo.insert()

    case result do
      {:ok, result} ->
        {:ok, Repo.preload(result, :measurement_unit)}

      {:eror, problem} ->
        {:error, problem}
    end
  end

  def add_items_from_recipe(basket_id, recipe, servings_scale \\ 1) do
    basket = get_shopping_basket!(basket_id)

    items =
      Enum.map(recipe.ingredients, fn ingredient ->
        %{
          list_id: basket.id,
          name: ingredient.name,
          quantity: ingredient.quantity * servings_scale,
          unit: ingredient.unit,
          nutrition_data: ingredient.nutrition,
          recipe_id: recipe.id,
          checked: false
        }
      end)

    Repo.insert_all(BasketItem, items)
  end

  def add_items_from_calendar_span(basket_id, start_date, end_date) do
    # Fetch all planned meals in date range
    planned_meals =
      Repo.all(
        from pm in PlannedMeal,
          where: pm.date >= ^start_date and pm.date <= ^end_date,
          preload: [recipe: [:ingredients]]
      )

    items =
      Enum.flat_map(planned_meals, fn meal ->
        Enum.map(meal.recipe.ingredients, fn ingredient ->
          %{
            list_id: basket_id,
            name: ingredient.name,
            quantity: ingredient.quantity,
            unit: ingredient.unit,
            recipe_id: meal.recipe_id,
            meal_plan_id: meal.id,
            checked: false
          }
        end)
      end)

    Repo.insert_all(BasketItem, items)
  end

  def create_shopping_basket(attrs \\ %{}) do
    result =
      %ShoppingBasket{}
      |> ShoppingBasket.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, basket} ->
        basket =
          basket
          |> Repo.preload(
            basket_ingredients: [
              :measurement_unit,
              ingredient: [
                :category,
                :ingredient_translation
              ]
            ]
          )

        {:ok, basket}

      _ ->
        result
    end
  end

  @doc """
  Deletes a shopping_basket.

  ## Examples

      iex> delete_shopping_basket(shopping_basket)
      {:ok, %ShoppingBasket{}}

      iex> delete_shopping_basket(shopping_basket)
      {:error, %Ecto.Changeset{}}

  """
  def delete_shopping_basket(%ShoppingBasket{} = shopping_basket) do
    Repo.delete(shopping_basket)
  end

  def delete_all_baskets_for_user(user_id) do
    from(basket in ShoppingBasket,
      where: basket.user_id == ^user_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking shopping_basket changes.

  ## Examples

      iex> change_shopping_basket(shopping_basket)
      %Ecto.Changeset{data: %ShoppingBasket{}}

  """
  def change_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs \\ %{}) do
    ShoppingBasket.changeset(shopping_basket, attrs)
  end

  alias Mehungry.Inventory.BasketIngredient

  @doc """
  Returns the list of basket_ingredients.

  ## Examples

      iex> list_basket_ingredients()
      [%BasketIngredient{}, ...]

  """
  def list_basket_ingredients do
    Repo.all(BasketIngredient)
  end

  @doc """
  Gets a single basket_ingredient.

  Raises `Ecto.NoResultsError` if the Ingredient basket does not exist.

  ## Examples

      iex> get_shopping_basket_ingredient!(123)
      %BasketIngredient{}

      iex> get_shopping_basket_ingredient!(456)
      ** (Ecto.NoResultsError)

  """
  def get_shopping_basket_ingredient!(id), do: Repo.get!(BasketIngredient, id)

  @doc """
  Creates a basket_ingredient.

  ## Examples

      iex> create_basket_ingredient(%{field: value})
      {:ok, %BasketIngredient{}}

      iex> create_basket_ingredient(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_basket_ingredient(attrs \\ %{}) do
    %BasketIngredient{}
    |> BasketIngredient.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a basket_ingredient.

  ## Examples

      iex> update_basket_ingredient(basket_ingredient, %{field: new_value})
      {:ok, %BasketIngredient{}}

      iex> update_basket_ingredient(basket_ingredient, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs) do
    basket_ingredient
    |> BasketIngredient.changeset(attrs)
    |> Repo.update()
  end

  def toggle_basket_ingredient(%BasketItem{} = basket_item) do
    basket_item
    |> BasketItem.changeset(%{in_storage: not basket_item.in_storage})
    |> Repo.update()
  end

  def toggle_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
    basket_ingredient
    |> BasketIngredient.changeset(%{in_storage: not basket_ingredient.in_storage})
    |> Repo.update()
  end

  @doc """
  Deletes a basket_ingredient.

  ## Examples

      iex> delete_basket_ingredient(basket_ingredient)
      {:ok, %BasketIngredient{}}

      iex> delete_basket_ingredient(basket_ingredient)
      {:error, %Ecto.Changeset{}}

  """
  def delete_basket_ingredient(%BasketIngredient{} = basket_ingredient) do
    Repo.delete(basket_ingredient)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking basket_ingredient changes.

  ## Examples

      iex> change_basket_ingredient(basket_ingredient)
      %Ecto.Changeset{data: %BasketIngredient{}}

  """
  def change_basket_ingredient(%BasketIngredient{} = basket_ingredient, attrs \\ %{}) do
    BasketIngredient.changeset(basket_ingredient, attrs)
  end
end
