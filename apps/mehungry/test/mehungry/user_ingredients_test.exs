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

  # The user-facing ingredient pickers search via IngredientSearch.search, which
  # hides the composite/prepared "second layer" USDA categories. A user's own
  # ingredient must never be hidden by that filter, whatever category they pick.
  describe "IngredientSearch.search/3 second-layer categories" do
    setup do
      # Build a genuine second-layer category directly (the shared category_fixture
      # dedups on a mis-spelled key and can't reliably create a named category).
      # "Baked Products" is one of the titles get_second_layer_foods_ids/0 hides.
      baked =
        Food.get_category_by_name("Baked Products") ||
          (
            {:ok, c} = Food.create_category(%{name: "Baked Products", description: "x"})
            c
          )

      %{baked: baked, mu: measurement_unit_fixture()}
    end

    test "owner's private ingredient in a hidden category is still found", %{
      baked: baked,
      mu: mu
    } do
      owner = user_fixture()

      {:ok, private} =
        Food.create_user_ingredient(owner, %{
          name: "Sourdough Zonkbread",
          description: "custom",
          category_id: baked.id,
          measurement_unit_id: mu.id
        })

      owner_ids =
        "Zonkbread" |> IngredientSearch.search([], owner.id) |> Enum.map(& &1.id)

      assert private.id in owner_ids
    end

    test "the same category still hides global ingredients from search", %{
      baked: baked,
      mu: mu
    } do
      {:ok, global} =
        Food.create_ingredient(%{
          name: "Plain Zonkloaf",
          description: "shared",
          category_id: baked.id,
          measurement_unit_id: mu.id
        })

      owner = user_fixture()

      owner_ids =
        "Zonkloaf" |> IngredientSearch.search([], owner.id) |> Enum.map(& &1.id)

      anon_ids = "Zonkloaf" |> IngredientSearch.search([], nil) |> Enum.map(& &1.id)

      refute global.id in owner_ids
      refute global.id in anon_ids
    end
  end
end
