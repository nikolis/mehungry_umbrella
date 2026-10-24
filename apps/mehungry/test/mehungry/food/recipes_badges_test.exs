defmodule Mehungry.Food.RecipesBadgesTest do
  @moduledoc """
  Persistence/query coverage for the `recipes.badges` column (see
  `Food.NutrientClaims` + `Recipes.put_nutrient_info/2`).
  """
  use Mehungry.DataCase, async: true

  alias Mehungry.{Food, Repo}
  alias Mehungry.Food.{IngredientNutrient, MeasurementUnit, Nutrient, Recipe, Recipes}
  alias Mehungry.FoodFixtures

  defp insert_recipe(badges) do
    %Recipe{}
    |> Ecto.Changeset.change(%{title: "r#{System.unique_integer([:positive])}", badges: badges})
    |> Repo.insert!()
  end

  defp insert_recipe(badges, attrs) do
    %Recipe{}
    |> Ecto.Changeset.change(
      Map.merge(%{title: "r#{System.unique_integer([:positive])}", badges: badges}, attrs)
    )
    |> Repo.insert!()
  end

  @iron_high [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}]

  # An ingredient carrying one iron IngredientNutrient (mg per 100 g).
  defp iron_ingredient(mg_unit, mg_per_100g) do
    nutrient =
      Repo.insert!(%Nutrient{name: "Iron, Fe", number: "303", measurement_unit_id: mg_unit.id})

    ingredient = FoodFixtures.ingredient_fixture()
    Repo.insert!(%IngredientNutrient{ingredient_id: ingredient.id, nutrient_id: nutrient.id, amount: mg_per_100g})
    ingredient
  end

  # Runs the write-path badge computation for a recipe made of `{ingredient, grams}`
  # pairs (grams via a gram-family unit, so no portion lookup is needed) and returns
  # the badges the changeset would persist.
  defp computed_badges(gram_unit, ingredient_grams) do
    recipe_ingredients =
      Enum.map(ingredient_grams, fn {ingredient, grams} ->
        %{
          ingredient_id: ingredient.id,
          measurement_unit_id: gram_unit.id,
          quantity: grams,
          ingredient_portion_id: nil
        }
      end)

    # get_field (not get_change): below the floor the computed `[]` equals the
    # struct's default, so Ecto records no change — the effective value is still [].
    %Recipe{}
    |> Ecto.Changeset.change()
    |> Recipes.put_nutrient_info(%{servings: 1, recipe_ingredients: recipe_ingredients})
    |> Ecto.Changeset.get_field(:badges)
  end

  describe "recipes_with_badge/2" do
    test "filters by nutrient label and level" do
      iron_high = insert_recipe([%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}])
      iron_source = insert_recipe([%{"nutrient" => "Iron", "level" => "source", "percent_nrv" => 18}])
      _calcium = insert_recipe([%{"nutrient" => "Calcium", "level" => "high", "percent_nrv" => 60}])

      high_iron = Food.recipes_with_badge("Iron") |> Repo.all() |> Enum.map(& &1.id)
      assert iron_high.id in high_iron
      refute iron_source.id in high_iron

      source_iron = Food.recipes_with_badge("Iron", "source") |> Repo.all() |> Enum.map(& &1.id)
      assert iron_source.id in source_iron
      refute iron_high.id in source_iron
    end

    test "ignores recipes with no badges" do
      plain = insert_recipe([])
      ids = Food.recipes_with_badge("Iron") |> Repo.all() |> Enum.map(& &1.id)
      refute plain.id in ids
    end
  end

  describe "search_recipes_by_badge/3 (public crawlable listing)" do
    test "returns only public, image-bearing recipes carrying the high badge" do
      # language_name set so the reused localization path doesn't build a
      # `lan.name == nil` query (real recipes always carry a language).
      pub = %{image_url: "https://img/x.jpg", private: false, language_name: "En"}
      public = insert_recipe(@iron_high, pub)
      private = insert_recipe(@iron_high, %{pub | image_url: "https://img/y.jpg", private: true})
      imageless = insert_recipe(@iron_high, %{pub | image_url: nil})

      source_only =
        insert_recipe(
          [%{"nutrient" => "Iron", "level" => "source", "percent_nrv" => 18}],
          %{pub | image_url: "https://img/z.jpg"}
        )

      # Assert on the composed query (the logic this function adds); the first-page
      # localization/pagination it also returns is pre-existing, separately-tested
      # machinery that needs language-associated recipe rows.
      {query, {_recipes, _cursor}} = Food.search_recipes_by_badge("Iron")
      ids = query |> Repo.all() |> Enum.map(& &1.id)

      assert public.id in ids
      refute private.id in ids
      refute imageless.id in ids
      refute source_only.id in ids
    end
  end

  describe "put_nutrient_info/2 badge assignment" do
    test "clears stale badges when the recipe has no nutrition" do
      changeset =
        Ecto.Changeset.change(%Recipe{
          badges: [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}]
        })

      result = Recipes.put_nutrient_info(changeset, %{recipe_ingredients: []})

      assert Ecto.Changeset.get_change(result, :badges) == []
    end

    test "awards a badge when nutrient-data coverage is above the floor" do
      gram = FoodFixtures.measurement_unit_fixture(%{name: "g"})
      mg = Repo.insert!(%MeasurementUnit{name: "mg"})
      iron = iron_ingredient(mg, 10.0)
      bulk = FoodFixtures.ingredient_fixture(%{name: "Data-less Bulk"})

      # 100 g iron ingredient (→ 10 mg iron = 71% of the 14 mg NRV) + 10 g of a
      # data-less ingredient → coverage 100/110 ≈ 0.91, above the floor.
      badges = computed_badges(gram, [{iron, 100}, {bulk, 10}])

      assert Enum.any?(badges, &(&1["nutrient"] == "Iron" and &1["level"] == "high"))
    end

    test "suppresses all badges when nutrient-data coverage is below the floor" do
      gram = FoodFixtures.measurement_unit_fixture(%{name: "g"})
      mg = Repo.insert!(%MeasurementUnit{name: "mg"})
      iron = iron_ingredient(mg, 10.0)
      bulk = FoodFixtures.ingredient_fixture(%{name: "Data-less Bulk"})

      # Same iron ingredient, but now swamped by 900 g of a data-less ingredient →
      # coverage 100/1000 = 0.10, far below the floor: the totals undercount, so no
      # claim can be trusted even though the iron value alone would earn a badge.
      badges = computed_badges(gram, [{iron, 100}, {bulk, 900}])

      assert badges == []
    end
  end
end
