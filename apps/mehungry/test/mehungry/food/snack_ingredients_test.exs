defmodule Mehungry.Food.SnackIngredientsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures, only: [ingredient_fixture: 1]
  import Mehungry.AccountsFixtures, only: [user_fixture: 0]

  alias Mehungry.Food.{Category, Ingredient, SnackIngredients}
  alias Mehungry.Repo

  setup do
    nuts =
      Repo.insert!(%Category{
        name: "Nut test #{System.unique_integer([:positive])}",
        description: "nuts"
      })

    almond = in_category(ingredient_fixture(%{name: "Nuts, almonds"}), nuts)
    walnut = in_category(ingredient_fixture(%{name: "Nuts, walnuts, english"}), nuts)
    milk = ingredient_fixture(%{name: "Almond milk, unsweetened"})

    %{almond: almond, walnut: walnut, milk: milk}
  end

  defp in_category(ingredient, category) do
    ingredient |> Ecto.Changeset.change(category_id: category.id) |> Repo.update!()
  end

  test "add is idempotent and remove deletes", %{almond: almond} do
    assert {:ok, _} = SnackIngredients.add(almond.id)
    assert {:ok, _} = SnackIngredients.add(almond.id)
    assert SnackIngredients.selected_ids() == MapSet.new([almond.id])

    assert [%{ingredient: %{name: "Nuts, almonds", category: %Category{}}}] =
             SnackIngredients.list_selected()

    assert SnackIngredients.remove(almond.id) == 1
    assert SnackIngredients.selected_ids() == MapSet.new()
  end

  test "search restricts to nut categories by default", %{almond: almond, milk: milk} do
    ids = "almond" |> SnackIngredients.search_candidates() |> Enum.map(& &1.id)
    assert almond.id in ids
    refute milk.id in ids

    ids = "almond" |> SnackIngredients.search_candidates(nuts_only: false) |> Enum.map(& &1.id)
    assert almond.id in ids and milk.id in ids
  end

  test "blank search lists the whole nut category", %{almond: a, walnut: w} do
    ids = "" |> SnackIngredients.search_candidates(limit: 10_000) |> Enum.map(& &1.id)
    assert a.id in ids and w.id in ids
    assert SnackIngredients.search_candidates("", nuts_only: false) == []
  end

  test "user-owned ingredients are never candidates", %{almond: almond} do
    user = user_fixture()

    almond
    |> Ecto.Changeset.change(user_id: user.id)
    |> Repo.update!()

    ids = "almond" |> SnackIngredients.search_candidates() |> Enum.map(& &1.id)
    refute almond.id in ids
    assert %Ingredient{} = Repo.get(Ingredient, almond.id)
  end
end
