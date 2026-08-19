defmodule Mehungry.Food.DietModeTest do
  use Mehungry.DataCase

  alias Mehungry.Food

  # Derive the excluded-category ids from Food.diet_category_ids/2 rather than
  # assuming a clean DB — the test env is seeded with the USDA animal categories
  # ("Beef Products", "Dairy and Egg Products", …).
  setup do
    for name <- ~w(Beef Poultry Dairy Pork Sausages Lamb Fish), do: ensure_category(name)

    vegan = Food.diet_category_ids(:vegan)
    vegetarian = Food.diet_category_ids(:vegetarian)
    %{vegan: vegan, vegetarian: vegetarian}
  end

  defp ensure_category(name) do
    Food.get_category_by_name(name) ||
      (Food.create_category(%{name: name, description: "x"}) |> elem(1))
  end

  test "excluding every vegan-excluded category yields :vegan", %{vegan: vegan} do
    rules = Enum.map(vegan, fn id -> %{category_id: id} end)
    assert Food.diet_mode_for_category_rules(rules) == :vegan
  end

  test "excluding the vegetarian set (dairy allowed) yields :vegetarian", %{vegetarian: vegetarian} do
    rules = Enum.map(vegetarian, fn id -> %{category_id: id} end)
    assert Food.diet_mode_for_category_rules(rules) == :vegetarian
  end

  test "no rules yields nil" do
    assert Food.diet_mode_for_category_rules([]) == nil
  end

  test "a partial exclusion (only one category) yields nil", %{vegan: vegan} do
    # A single excluded category can't cover either full diet set (there are
    # several distinct animal categories), so no mode is inferred.
    rules = [%{category_id: List.first(vegan)}]
    assert Food.diet_mode_for_category_rules(rules) == nil
  end

  test "accepts a bare list of category ids", %{vegan: vegan} do
    assert Food.diet_mode_for_category_rules(vegan) == :vegan
  end
end
