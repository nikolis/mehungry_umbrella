defmodule Mehungry.InventoryTest do
  use Mehungry.DataCase

  alias Mehungry.Inventory

  describe "shoping_baskets" do
    alias Mehungry.Inventory.ShopingBasket

    import Mehungry.InventoryFixtures

    @invalid_attrs %{end_dt: nil, start_dt: nil}

    test "list_shoping_baskets/0 returns all shoping_baskets" do
      shoping_basket = shoping_basket_fixture()
      assert Inventory.list_shoping_baskets() == [shoping_basket]
    end

    test "get_shoping_basket!/1 returns the shoping_basket with given id" do
      shoping_basket = shoping_basket_fixture()
      assert Inventory.get_shoping_basket!(shoping_basket.id) == shoping_basket
    end

    test "create_shoping_basket/1 with valid data creates a shoping_basket" do
      valid_attrs = %{end_dt: ~N[2023-01-25 11:01:00], start_dt: ~N[2023-01-25 11:01:00]}

      assert {:ok, %ShopingBasket{} = shoping_basket} = Inventory.create_shoping_basket(valid_attrs)
      assert shoping_basket.end_dt == ~N[2023-01-25 11:01:00]
      assert shoping_basket.start_dt == ~N[2023-01-25 11:01:00]
    end

    test "create_shoping_basket/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_shoping_basket(@invalid_attrs)
    end

    test "update_shoping_basket/2 with valid data updates the shoping_basket" do
      shoping_basket = shoping_basket_fixture()
      update_attrs = %{end_dt: ~N[2023-01-26 11:01:00], start_dt: ~N[2023-01-26 11:01:00]}

      assert {:ok, %ShopingBasket{} = shoping_basket} = Inventory.update_shoping_basket(shoping_basket, update_attrs)
      assert shoping_basket.end_dt == ~N[2023-01-26 11:01:00]
      assert shoping_basket.start_dt == ~N[2023-01-26 11:01:00]
    end

    test "update_shoping_basket/2 with invalid data returns error changeset" do
      shoping_basket = shoping_basket_fixture()
      assert {:error, %Ecto.Changeset{}} = Inventory.update_shoping_basket(shoping_basket, @invalid_attrs)
      assert shoping_basket == Inventory.get_shoping_basket!(shoping_basket.id)
    end

    test "delete_shoping_basket/1 deletes the shoping_basket" do
      shoping_basket = shoping_basket_fixture()
      assert {:ok, %ShopingBasket{}} = Inventory.delete_shoping_basket(shoping_basket)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_shoping_basket!(shoping_basket.id) end
    end

    test "change_shoping_basket/1 returns a shoping_basket changeset" do
      shoping_basket = shoping_basket_fixture()
      assert %Ecto.Changeset{} = Inventory.change_shoping_basket(shoping_basket)
    end
  end

  describe "ingredient_baskets" do
    alias Mehungry.Inventory.IngredientBasket

    import Mehungry.InventoryFixtures

    @invalid_attrs %{quantity: nil}

    test "list_ingredient_baskets/0 returns all ingredient_baskets" do
      ingredient_basket = ingredient_basket_fixture()
      assert Inventory.list_ingredient_baskets() == [ingredient_basket]
    end

    test "get_ingredient_basket!/1 returns the ingredient_basket with given id" do
      ingredient_basket = ingredient_basket_fixture()
      assert Inventory.get_ingredient_basket!(ingredient_basket.id) == ingredient_basket
    end

    test "create_ingredient_basket/1 with valid data creates a ingredient_basket" do
      valid_attrs = %{quantity: 120.5}

      assert {:ok, %IngredientBasket{} = ingredient_basket} = Inventory.create_ingredient_basket(valid_attrs)
      assert ingredient_basket.quantity == 120.5
    end

    test "create_ingredient_basket/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Inventory.create_ingredient_basket(@invalid_attrs)
    end

    test "update_ingredient_basket/2 with valid data updates the ingredient_basket" do
      ingredient_basket = ingredient_basket_fixture()
      update_attrs = %{quantity: 456.7}

      assert {:ok, %IngredientBasket{} = ingredient_basket} = Inventory.update_ingredient_basket(ingredient_basket, update_attrs)
      assert ingredient_basket.quantity == 456.7
    end

    test "update_ingredient_basket/2 with invalid data returns error changeset" do
      ingredient_basket = ingredient_basket_fixture()
      assert {:error, %Ecto.Changeset{}} = Inventory.update_ingredient_basket(ingredient_basket, @invalid_attrs)
      assert ingredient_basket == Inventory.get_ingredient_basket!(ingredient_basket.id)
    end

    test "delete_ingredient_basket/1 deletes the ingredient_basket" do
      ingredient_basket = ingredient_basket_fixture()
      assert {:ok, %IngredientBasket{}} = Inventory.delete_ingredient_basket(ingredient_basket)
      assert_raise Ecto.NoResultsError, fn -> Inventory.get_ingredient_basket!(ingredient_basket.id) end
    end

    test "change_ingredient_basket/1 returns a ingredient_basket changeset" do
      ingredient_basket = ingredient_basket_fixture()
      assert %Ecto.Changeset{} = Inventory.change_ingredient_basket(ingredient_basket)
    end
  end
end
