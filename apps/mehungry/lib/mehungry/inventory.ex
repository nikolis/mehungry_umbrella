defmodule Mehungry.Inventory do
  @moduledoc """
  The Inventory context.
  """

  import Ecto.Query, warn: false
  alias Mehungry.Repo

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
      basket_ingredients: [
        ingredient: [
          :measurement_unit,
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
      basket_ingredients: [
        ingredient: [
          :measurement_unit,
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
              ingredient: [
                :measurement_unit,
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
  Updates a shopping_basket.

  ## Examples

      iex> update_shopping_basket(shopping_basket, %{field: new_value})
      {:ok, %ShoppingBasket{}}

      iex> update_shopping_basket(shopping_basket, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_shopping_basket(%ShoppingBasket{} = shopping_basket, attrs) do
    shopping_basket
    |> ShoppingBasket.changeset(attrs)
    |> Repo.update()
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

      iex> get_basket_ingredient!(123)
      %BasketIngredient{}

      iex> get_basket_ingredient!(456)
      ** (Ecto.NoResultsError)

  """
  def get_basket_ingredient!(id), do: Repo.get!(BasketIngredient, id)

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
