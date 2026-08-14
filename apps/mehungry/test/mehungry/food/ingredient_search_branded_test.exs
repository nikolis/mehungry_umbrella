defmodule Mehungry.Food.IngredientSearchBrandedTest do
  @moduledoc """
  User-facing ingredient search must exclude USDA "Branded" rows (so they don't
  pollute results and so the `*_active_idx` partial indexes are usable), while
  admin search can still reach them.
  """
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.IngredientSearch

  setup do
    plain = ingredient_fixture(%{name: "zzqsalt table", food_class: "Foundation"})
    branded = ingredient_fixture(%{name: "zzqsalt megabrand snack", food_class: "Branded"})
    %{plain: plain, branded: branded}
  end

  # User-facing name search goes through IngredientSearch.search (the single
  # user path); it must drop Branded rows. Admin search can still reach them.
  test "IngredientSearch.search/1 excludes Branded rows", %{plain: plain, branded: branded} do
    ids = "zzqsalt" |> IngredientSearch.search() |> Enum.map(& &1.id)

    assert plain.id in ids
    refute branded.id in ids
  end

  test "admin search_ingredient_alt_admin can still filter to Branded", %{branded: branded} do
    {_query, {ingredients, _cursor}, _count} =
      Food.search_ingredient_alt_admin("zzqsalt", ["Branded"])

    ids = Enum.map(ingredients, & &1.id)

    assert branded.id in ids
  end
end
