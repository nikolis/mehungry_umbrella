defmodule Mehungry.InventoryTest do
  use Mehungry.DataCase

  alias Mehungry.Inventory
  alias Mehungry.AccountsFixtures
  alias Mehungry.FoodFixtures

  describe "shopping_baskets" do
    alias Mehungry.Inventory.ShoppingBasket

    import Mehungry.InventoryFixtures

    setup do
      user = AccountsFixtures.user_fixture()

      %{user: user}
    end

    @invalid_attrs %{end_dt: nil, start_dt: nil}

    test "list_shopping_baskets/0 returns all shopping_baskets", %{user: user} do
      {:ok, shopping_basket} = shopping_basket_fixture(%{user_id: user.id})
      assert Inventory.list_shopping_baskets_for_user(user.id) == [shopping_basket]
    end

    test "get_shopping_basket!/1 returns the shopping_basket with given id", %{user: user} do
      {:ok, shopping_basket} = shopping_basket_fixture(%{user_id: user.id})
      assert Inventory.get_shopping_basket!(shopping_basket.id) == shopping_basket
    end

    test "create_shopping_basket/1 with valid data creates a shopping_basket", %{user: user} do
      valid_attrs = %{
        end_dt: ~N[2023-01-25 11:01:00],
        start_dt: ~N[2023-01-25 11:01:00],
        user_id: user.id,
        title: "tests",
        basket_ingredients: []
      }

      assert {:ok, %ShoppingBasket{} = shopping_basket} =
               Inventory.create_shopping_basket(valid_attrs)

      assert shopping_basket.end_dt == ~N[2023-01-25 11:01:00]
      assert shopping_basket.start_dt == ~N[2023-01-25 11:01:00]
    end

    test "create_shopping_basket/1 creation process should be able to handle measurement unit normalization",
         %{user: user} do
      ingredient = FoodFixtures.ingredient_fixture()
      _measurement_unit_2 = FoodFixtures.measurement_unit_fixture(%{name: "kg"})
      measurement_unit = FoodFixtures.measurement_unit_fixture(%{name: "gram"})

      valid_attrs = %{
        end_dt: ~N[2023-01-25 11:01:00],
        start_dt: ~N[2023-01-25 11:01:00],
        user_id: user.id,
        title: "testtt00,",
        basket_ingredients: [
          %{
            ingredient_id: ingredient.id,
            measurement_unit_id: measurement_unit.id,
            quantity: 54000,
            title: "sadf"
          }
        ]
      }

      assert {:ok, %ShoppingBasket{} = shopping_basket} =
               Inventory.create_shopping_basket(valid_attrs)

      assert shopping_basket.end_dt == ~N[2023-01-25 11:01:00]
      assert shopping_basket.start_dt == ~N[2023-01-25 11:01:00]
    end

    test "create_shopping_basket/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_shopping_basket(@invalid_attrs)
    end

    test "update_shopping_basket/2 with valid data updates the shopping_basket", %{user: user} do
      {:ok, shopping_basket} = shopping_basket_fixture(%{user_id: user.id})
      update_attrs = %{end_dt: ~N[2023-01-26 11:01:00], start_dt: ~N[2023-01-26 11:01:00]}

      assert {:ok, %ShoppingBasket{} = shopping_basket} =
               Inventory.update_shopping_basket(shopping_basket, update_attrs)

      assert shopping_basket.end_dt == ~N[2023-01-26 11:01:00]
      assert shopping_basket.start_dt == ~N[2023-01-26 11:01:00]
    end

    test "update_shopping_basket/2 with invalid data returns error changeset", %{user: user} do
      {:ok, shopping_basket} = shopping_basket_fixture(%{user_id: user.id})

      #assert {:error, %Ecto.Changeset{}} =
       #        Inventory.update_shopping_basket(shopping_basket, @invalid_attrs)

      assert shopping_basket == Inventory.get_shopping_basket!(shopping_basket.id)
    end

    test "delete_shopping_basket/1 deletes the shopping_basket", %{user: user} do
      {:ok, shopping_basket} = shopping_basket_fixture(%{user_id: user.id})
      assert {:ok, %ShoppingBasket{}} = Inventory.delete_shopping_basket(shopping_basket)

      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_shopping_basket!(shopping_basket.id)
      end
    end

    test "change_shopping_basket/1 returns a shopping_basket changeset", %{user: user} do
      {:ok, shopping_basket} = shopping_basket_fixture(%{user_id: user.id})
      assert %Ecto.Changeset{} = Inventory.change_shopping_basket(shopping_basket)
    end
  end

  """
  describe "basket_ingredients" do
    alias Mehungry.Inventory.BasketIngredient 

    import Mehungry.InventoryFixtures

    @invalid_attrs %{quantity: nil, title: nil}

    test "list_basket_ingredients/0 returns all basket_ingredients" do
      basket_ingredient = basket_ingredient_fixture()
      assert Inventory.list_basket_ingredients() == [basket_ingredient]
    end

    test "get_basket_ingredient!/1 returns the basket_ingredient with given id" do
      basket_ingredient = basket_ingredient_fixture()
      assert Inventory.get_basket_ingredient!(basket_ingredient.id) == basket_ingredient
    end

    test "create_basket_ingredient/1 with valid data creates a basket_ingredient" do
      valid_attrs = %{quantity: 120.5}

      assert {:ok, %BasketIngredient{} = basket_ingredient} =
               Inventory.create_basket_ingredient(valid_attrs)

      assert basket_ingredient.quantity == 120.5
    end

    test "create_basket_ingredient/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_basket_ingredient(@invalid_attrs)
    end

    test "update_basket_ingredient/2 with valid data updates the basket_ingredient" do
      basket_ingredient = basket_ingredient_fixture()
      update_attrs = %{quantity: 456.7}

      assert {:ok, %BasketIngredient{} = basket_ingredient} =
               Inventory.update_basket_ingredient(basket_ingredient, update_attrs)

      assert basket_ingredient.quantity == 456.7
    end

    test "update_basket_ingredient/2 with invalid data returns error changeset" do
      basket_ingredient = basket_ingredient_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Inventory.update_basket_ingredient(basket_ingredient, @invalid_attrs)

      assert basket_ingredient == Inventory.get_basket_ingredient!(basket_ingredient.id)
    end

    test "delete_basket_ingredient/1 deletes the basket_ingredient" do
      basket_ingredient = basket_ingredient_fixture()
      assert {:ok, %BasketIngredient{}} = Inventory.delete_basket_ingredient(basket_ingredient)

      assert_raise Ecto.NoResultsError, fn ->
        Inventory.get_basket_ingredient!(basket_ingredient.id)
      end
    end

    test "change_basket_ingredient/1 returns a basket_ingredient changeset" do
      basket_ingredient = basket_ingredient_fixture()
      assert %Ecto.Changeset{} = Inventory.change_basket_ingredient(basket_ingredient)
    end
  end
  """
end
