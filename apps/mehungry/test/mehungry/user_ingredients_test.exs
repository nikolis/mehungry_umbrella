defmodule Mehungry.UserIngredientsTest do
  use Mehungry.DataCase

  alias Mehungry.Food
  alias Mehungry.Food.IngredientSearch

  import Mehungry.{FoodFixtures, AccountsFixtures}

  # Builds valid attrs for a user-created ingredient with a distinctive name so
  # search can find it.
  defp user_ingredient_attrs(name) do
    category = category_fixture(%{})
    mu = measurement_unit_fixture()

    %{
      name: name,
      description: "custom",
      category_id: category.id,
      measurement_unit_id: mu.id
    }
  end

  describe "create_user_ingredient/2" do
    test "stamps the owner and a User created food_class" do
      user = user_fixture()

      {:ok, ingredient} =
        Food.create_user_ingredient(user, user_ingredient_attrs("Zorbleberry"))

      assert ingredient.user_id == user.id
      assert ingredient.food_class == "User created"
      assert ingredient.search_name == "zorbleberry"
    end
  end

  describe "list_user_ingredients/1" do
    test "returns only the owner's ingredients" do
      owner = user_fixture()
      other = user_fixture()

      {:ok, mine} = Food.create_user_ingredient(owner, user_ingredient_attrs("Mine A"))
      {:ok, _theirs} = Food.create_user_ingredient(other, user_ingredient_attrs("Theirs A"))
      _global = ingredient_fixture()

      ids = owner |> Food.list_user_ingredients() |> Enum.map(& &1.id)

      assert ids == [mine.id]
    end
  end

  describe "get_user_ingredient!/2" do
    test "returns the owner's ingredient" do
      owner = user_fixture()
      {:ok, mine} = Food.create_user_ingredient(owner, user_ingredient_attrs("Mine B"))

      assert Food.get_user_ingredient!(owner, mine.id).id == mine.id
    end

    test "raises for another user's ingredient" do
      owner = user_fixture()
      other = user_fixture()
      {:ok, mine} = Food.create_user_ingredient(owner, user_ingredient_attrs("Mine C"))

      assert_raise Ecto.NoResultsError, fn ->
        Food.get_user_ingredient!(other, mine.id)
      end
    end
  end

  describe "IngredientSearch.search/3 visibility" do
    setup do
      owner = user_fixture()
      other = user_fixture()

      {:ok, private} =
        Food.create_user_ingredient(owner, user_ingredient_attrs("Wobblefruit"))

      %{owner: owner, other: other, private: private}
    end

    test "owner sees their own private ingredient", %{owner: owner, private: private} do
      ids = "Wobblefruit" |> IngredientSearch.search([], owner.id) |> Enum.map(& &1.id)
      assert private.id in ids
    end

    test "a different user does not see it", %{other: other, private: private} do
      ids = "Wobblefruit" |> IngredientSearch.search([], other.id) |> Enum.map(& &1.id)
      refute private.id in ids
    end

    test "anonymous (nil owner) does not see it", %{private: private} do
      ids = "Wobblefruit" |> IngredientSearch.search([], nil) |> Enum.map(& &1.id)
      refute private.id in ids
    end

    test "global ingredients remain visible to everyone" do
      global = ingredient_fixture(%{name: "Globalberry"})
      other = user_fixture()

      owner_ids = "Globalberry" |> IngredientSearch.search([], other.id) |> Enum.map(& &1.id)
      anon_ids = "Globalberry" |> IngredientSearch.search([], nil) |> Enum.map(& &1.id)

      assert global.id in owner_ids
      assert global.id in anon_ids
    end
  end

  # The calendar ingredient picker searches via search_ingredient_alt, which
  # hides the composite/prepared "second layer" USDA categories. A user's own
  # ingredient must never be hidden by that filter, whatever category they pick.
  describe "search_ingredient_alt/3 second-layer categories" do
    test "owner's private ingredient in a hidden category is still found" do
      owner = user_fixture()
      # "Baked Products" is one of the second-layer categories excluded from search.
      baked = category_fixture(%{name: "Baked Products"})
      mu = measurement_unit_fixture()

      {:ok, private} =
        Food.create_user_ingredient(owner, %{
          name: "Sourdough Zonkbread",
          description: "custom",
          category_id: baked.id,
          measurement_unit_id: mu.id
        })

      owner_ids =
        "Zonkbread" |> Food.search_ingredient_alt([], owner.id) |> Enum.map(& &1.id)

      assert private.id in owner_ids
    end

    test "the same category still hides global ingredients from search" do
      baked = category_fixture(%{name: "Baked Products"})
      global = ingredient_fixture(%{name: "Plain Zonkloaf", category_id: baked.id})
      owner = user_fixture()

      owner_ids =
        "Zonkloaf" |> Food.search_ingredient_alt([], owner.id) |> Enum.map(& &1.id)

      anon_ids = "Zonkloaf" |> Food.search_ingredient_alt([], nil) |> Enum.map(& &1.id)

      refute global.id in owner_ids
      refute global.id in anon_ids
    end
  end
end
