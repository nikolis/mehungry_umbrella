defmodule Mehungry.Food.DietClassifierTest do
  use Mehungry.DataCase

  alias Mehungry.Food
  alias Mehungry.Food.DietClassifier

  # classify/1 only reads `recipe_ingredients[].ingredient.category_id`, so we hand
  # it lightweight maps. The excluded-category ids come from Food.diet_category_ids/2,
  # so this test adapts to whatever animal categories exist (the seeded USDA set,
  # e.g. "Beef Products"/"Dairy and Egg Products") rather than assuming a clean DB.
  setup do
    # Guarantee the diet vocabulary exists so the test is independent of seeding.
    ensure_category("Beef")
    ensure_category("Dairy")

    # A meat category is excluded by *both* diets, so it lives in the
    # vegetarian-excluded set; Dairy is the vegan-only extra (vegan minus
    # vegetarian). Picking `animal_category_id` from the vegetarian set (rather
    # than `List.first(vegan_excluded)`, which can be Dairy) guarantees a true
    # meat category regardless of which categories happen to be seeded.
    meat_only = Food.diet_category_ids(:vegetarian)
    dairy_only = Food.diet_category_ids(:vegan) -- Food.diet_category_ids(:vegetarian)

    %{
      animal_category_id: List.first(meat_only),
      dairy_category_id: List.first(dairy_only)
    }
  end

  defp ensure_category(name) do
    Food.get_category_by_name(name) ||
      (Food.create_category(%{name: name, description: "x"}) |> elem(1))
  end

  defp plant_category_id do
    {:ok, category} =
      Food.create_category(%{
        name: "Leafy Greens #{System.unique_integer([:positive])}",
        description: "x"
      })

    category.id
  end

  defp recipe_with_categories(category_ids) do
    %{recipe_ingredients: Enum.map(category_ids, fn cid -> %{ingredient: %{category_id: cid}} end)}
  end

  test "a recipe with no animal categories is vegan and vegetarian" do
    assert DietClassifier.classify(recipe_with_categories([plant_category_id()])) ==
             ["vegan", "vegetarian"]
  end

  test "a recipe containing a meat category is neither", %{animal_category_id: beef_id} do
    refute is_nil(beef_id)
    assert DietClassifier.classify(recipe_with_categories([plant_category_id(), beef_id])) == []
  end

  test "a recipe whose only animal product is dairy is vegetarian but not vegan", %{
    dairy_category_id: dairy_id
  } do
    refute is_nil(dairy_id)

    assert DietClassifier.classify(recipe_with_categories([plant_category_id(), dairy_id])) ==
             ["vegetarian"]
  end

  test "every category a diet keyword matches is excluded, not just the first" do
    # "Lamb" substring-matches several seeded meat categories; all are meat, so a
    # recipe using an ingredient from any of them must not be tagged vegan/veg.
    ensure_category("Lamb, Veal, and Game Products")
    ensure_category("Lamb, goat, game")

    for name <- ["Lamb, Veal, and Game Products", "Lamb, goat, game"] do
      cid = Food.get_category_by_name(name).id

      assert DietClassifier.classify(recipe_with_categories([plant_category_id(), cid])) == [],
             "#{name} should count as meat"
    end
  end

  test "an ingredient with no category is not classified (conservative)" do
    recipe = recipe_with_categories([plant_category_id()])
    recipe = %{recipe | recipe_ingredients: recipe.recipe_ingredients ++ [%{ingredient: %{category_id: nil}}]}
    assert DietClassifier.classify(recipe) == []
  end

  test "a recipe with no ingredients is not classified" do
    assert DietClassifier.classify(%{recipe_ingredients: []}) == []
  end

  test "a recipe without loaded ingredients is not classified" do
    assert DietClassifier.classify(%{}) == []
  end
end
