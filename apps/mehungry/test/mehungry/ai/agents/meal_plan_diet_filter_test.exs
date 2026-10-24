defmodule Mehungry.AI.Agents.MealPlanDietFilterTest do
  @moduledoc """
  Deterministic coverage of the category-level diet enforcement the meal-plan
  agent now applies to `search_catalog` / `search_ingredients` — the fix for the
  substring gap (Vegan's "meat" not matching "chicken"). Tests the diet-mode
  derivation and the two Food query helpers the agent's search handlers use.
  No LLM.
  """
  use Mehungry.DataCase, async: false

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2, ingredient_fixture: 1]

  alias Mehungry.{Food, Repo}
  alias Mehungry.Food.{Categories, Category}
  alias Mehungry.Accounts.UserProfile
  alias Mehungry.AI.Agents.MealPlanAgent
  alias Mehungry.MealBlueprints.{Blueprint, DietPatterns}

  defp bp(descriptor), do: %Blueprint{avoid_foods: descriptor.avoid_foods}

  describe "diet_mode_from_blueprint/1" do
    test "maps the vegan patterns to :vegan" do
      assert MealPlanAgent.diet_mode_from_blueprint(bp(DietPatterns.get(:vegan))) == :vegan
      assert MealPlanAgent.diet_mode_from_blueprint(bp(DietPatterns.get(:whole_food_plant_based))) ==
               :vegan
    end

    test "maps the vegetarian pattern to :vegetarian" do
      assert MealPlanAgent.diet_mode_from_blueprint(bp(DietPatterns.get(:vegetarian))) ==
               :vegetarian
    end

    test "maps the pescatarian pattern to :pescatarian (meat+poultry, fish kept)" do
      assert MealPlanAgent.diet_mode_from_blueprint(bp(DietPatterns.get(:pescatarian))) ==
               :pescatarian
    end

    test "non-category diets and nil → nil" do
      assert MealPlanAgent.diet_mode_from_blueprint(bp(DietPatterns.get(:mediterranean))) == nil
      assert MealPlanAgent.diet_mode_from_blueprint(bp(DietPatterns.get(:ketogenic))) == nil
      assert MealPlanAgent.diet_mode_from_blueprint(nil) == nil
    end
  end

  describe "effective_diet_mode/2" do
    test "a vegan blueprint wins regardless of profile" do
      user = user_fixture()
      assert MealPlanAgent.effective_diet_mode(user.id, bp(DietPatterns.get(:vegan))) == :vegan
    end

    test "falls back to the user's persisted profile diet" do
      user = user_fixture()
      set_profile_diet(user.id, "vegetarian")
      assert MealPlanAgent.effective_diet_mode(user.id, nil) == :vegetarian
    end

    test "nil when neither blueprint nor profile set a diet" do
      user = user_fixture()
      set_profile_diet(user.id, "omnivore")
      assert MealPlanAgent.effective_diet_mode(user.id, nil) == nil
    end
  end

  describe "category filtering — the gate the search handlers apply" do
    setup do
      user = user_fixture()

      # Use the real seeded diet categories (the fixture's category_fixture can't
      # place an ingredient in a named category — a typo makes it ignore it).
      excluded = Categories.diet_category_ids(:vegan)
      beef_cat_id = hd(excluded)
      veg_cat = Repo.all(Category) |> Enum.find(&(&1.id not in excluded))

      beef_ing = categorized_ingredient("Ground Beef", beef_cat_id)
      veg_ing = categorized_ingredient("Spinach", veg_cat.id)

      beef_recipe =
        recipe_fixture(user, %{title: "Beef and Vegetable Stew", recipe_ingredients: [ri(beef_ing)]})

      veg_recipe =
        recipe_fixture(user, %{title: "Spinach and Chickpea Bowl", recipe_ingredients: [ri(veg_ing)]})

      %{beef_ing: beef_ing, veg_ing: veg_ing, beef_recipe: beef_recipe, veg_recipe: veg_recipe}
    end

    test "recipe_ids_with_diet_tag(:vegan) drops the beef recipe, keeps the plant recipe", ctx do
      kept = Food.recipe_ids_with_diet_tag([ctx.beef_recipe.id, ctx.veg_recipe.id], :vegan)

      refute MapSet.member?(kept, ctx.beef_recipe.id),
             "a beef recipe must not survive the vegan filter (the substring 'meat' never would)"

      assert MapSet.member?(kept, ctx.veg_recipe.id)
    end

    test "recipe_ids_with_diet_tag with no diet mode keeps everything", ctx do
      ids = [ctx.beef_recipe.id, ctx.veg_recipe.id]
      assert Food.recipe_ids_with_diet_tag(ids, nil) == MapSet.new(ids)
    end

    test "ingredient_ids_in_categories flags the beef ingredient as vegan-excluded", ctx do
      excluded =
        Food.ingredient_ids_in_categories(
          [ctx.beef_ing.id, ctx.veg_ing.id],
          Categories.diet_category_ids(:vegan)
        )

      assert MapSet.member?(excluded, ctx.beef_ing.id)
      refute MapSet.member?(excluded, ctx.veg_ing.id)
    end
  end

  describe "pescatarian category filtering — fish kept, meat/poultry dropped" do
    setup do
      user = user_fixture()

      pescatarian_excluded = Categories.diet_category_ids(:pescatarian)
      # Fish/Dairy are vegan-excluded but pescatarian-*allowed*.
      allowed_animal = Categories.diet_category_ids(:vegan) -- pescatarian_excluded

      # These assertions document the seeded-data assumptions this test needs.
      assert pescatarian_excluded != [], "expected seeded meat/poultry categories"
      assert allowed_animal != [], "expected a seeded fish/dairy category"

      meat_cat_id = hd(pescatarian_excluded)
      fish_cat_id = hd(allowed_animal)
      veg_cat = Repo.all(Category) |> Enum.find(&(&1.id not in Categories.diet_category_ids(:vegan)))

      chicken_ing = categorized_ingredient("Chicken Breast", meat_cat_id)
      salmon_ing = categorized_ingredient("Salmon Fillet", fish_cat_id)
      veg_ing = categorized_ingredient("Kale", veg_cat.id)

      chicken_recipe =
        recipe_fixture(user, %{title: "Roast Chicken Dinner", recipe_ingredients: [ri(chicken_ing)]})

      salmon_recipe =
        recipe_fixture(user, %{title: "Grilled Salmon Bowl", recipe_ingredients: [ri(salmon_ing)]})

      veg_recipe =
        recipe_fixture(user, %{title: "Kale Caesar", recipe_ingredients: [ri(veg_ing)]})

      %{
        chicken_ing: chicken_ing,
        salmon_ing: salmon_ing,
        chicken_recipe: chicken_recipe,
        salmon_recipe: salmon_recipe,
        veg_recipe: veg_recipe
      }
    end

    test "pescatarian_recipe_ids keeps the salmon + plant recipe, drops the chicken recipe", ctx do
      ids = [ctx.chicken_recipe.id, ctx.salmon_recipe.id, ctx.veg_recipe.id]
      keep = Food.pescatarian_recipe_ids(ids)

      refute MapSet.member?(keep, ctx.chicken_recipe.id),
             "a chicken recipe must not survive the pescatarian filter"

      assert MapSet.member?(keep, ctx.salmon_recipe.id), "fish is pescatarian-allowed"
      assert MapSet.member?(keep, ctx.veg_recipe.id)
    end

    test "pescatarian_recipe_ids is conservative: an uncategorized ingredient drops the recipe" do
      user = user_fixture()

      uncategorized =
        %{name: "Mystery Paste"}
        |> ingredient_fixture()
        |> Ecto.Changeset.change(category_id: nil)
        |> Repo.update!()

      recipe =
        recipe_fixture(user, %{title: "Mystery Dish", recipe_ingredients: [ri(uncategorized)]})

      refute MapSet.member?(Food.pescatarian_recipe_ids([recipe.id]), recipe.id)
    end

    test "ingredient_ids_in_categories(:pescatarian) flags chicken, not salmon", ctx do
      excluded =
        Food.ingredient_ids_in_categories(
          [ctx.chicken_ing.id, ctx.salmon_ing.id],
          Categories.diet_category_ids(:pescatarian)
        )

      assert MapSet.member?(excluded, ctx.chicken_ing.id)
      refute MapSet.member?(excluded, ctx.salmon_ing.id)
    end
  end

  describe "required #raw hashtag gate — the layer on top of the diet filter" do
    setup do
      user = user_fixture()

      # recipe_fixture goes through Food.create_recipe → ensure_recipe_hashtags,
      # which parses #tags out of the description, so a "#raw" description links
      # the raw hashtag exactly as a user typing it would.
      raw_recipe =
        recipe_fixture(user, %{
          title: "Raw Zucchini Salad",
          description: "crisp and fresh #raw #cold"
        })

      cooked_recipe =
        recipe_fixture(user, %{title: "Zucchini Gratin", description: "baked and bubbling #cold"})

      %{user: user, raw_recipe: raw_recipe, cooked_recipe: cooked_recipe}
    end

    test "required_recipe_tags/1 reads a blueprint's required_hashtags (downcased, nil-safe)" do
      assert MealPlanAgent.required_recipe_tags(%Blueprint{required_hashtags: ["Raw", " raw "]}) ==
               ["raw"]

      assert MealPlanAgent.required_recipe_tags(%Blueprint{required_hashtags: []}) == []
      assert MealPlanAgent.required_recipe_tags(nil) == []
    end

    test "the raw patterns carry required_hashtags [\"raw\"]" do
      assert MealPlanAgent.required_recipe_tags(
               %Blueprint{required_hashtags: DietPatterns.get(:raw_vegan).required_hashtags}
             ) == ["raw"]

      assert MealPlanAgent.required_recipe_tags(
               %Blueprint{required_hashtags: DietPatterns.get(:raw_vegetarian).required_hashtags}
             ) == ["raw"]
    end

    test "recipe_ids_with_all_hashtags keeps only the #raw recipe for [\"raw\"]", ctx do
      ids = [ctx.raw_recipe.id, ctx.cooked_recipe.id]
      keep = Food.recipe_ids_with_all_hashtags(ids, ["raw"])

      assert MapSet.member?(keep, ctx.raw_recipe.id)
      refute MapSet.member?(keep, ctx.cooked_recipe.id)
    end

    test "recipe_ids_with_all_hashtags with [] applies no filter", ctx do
      ids = [ctx.raw_recipe.id, ctx.cooked_recipe.id]
      assert Food.recipe_ids_with_all_hashtags(ids, []) == MapSet.new(ids)
    end

    test "recipe_ids_with_all_hashtags requires EVERY tag (conjunction)", ctx do
      # The raw recipe carries #raw AND #cold; the cooked one carries only #cold.
      # Requiring both keeps only the recipe that has all of them.
      ids = [ctx.raw_recipe.id, ctx.cooked_recipe.id]
      keep = Food.recipe_ids_with_all_hashtags(ids, ["raw", "cold"])

      assert MapSet.member?(keep, ctx.raw_recipe.id)
      refute MapSet.member?(keep, ctx.cooked_recipe.id)
    end
  end

  defp set_profile_diet(user_id, diet) do
    {count, _} =
      from(p in UserProfile, where: p.user_id == ^user_id) |> Repo.update_all(set: [diet: diet])

    # user_fixture creates a profile; if it ever doesn't, insert one.
    if count == 0, do: user_profile_fixture(%{user_id: user_id, diet: diet})
  end

  defp categorized_ingredient(name, category_id) do
    ing = ingredient_fixture(%{name: name})
    {:ok, ing} = ing |> Ecto.Changeset.change(category_id: category_id) |> Repo.update()
    ing
  end

  defp ri(ing),
    do: %{ingredient_id: ing.id, measurement_unit_id: ing.measurement_unit_id, quantity: 100}
end
