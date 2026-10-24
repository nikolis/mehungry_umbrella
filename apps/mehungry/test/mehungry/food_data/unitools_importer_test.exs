defmodule Mehungry.FoodData.UniToolsImporterTest do
  @moduledoc """
  Covers the DB-backed mapping + matching of the UniTools importer
  (`build_recipe_attrs/3`) — field mapping, the CC BY-SA 4.0 licence/attribution
  stamped per recipe, structured-ingredient resolution (no free-text parse), the
  `unit_selection` seeded for the review form, photos skipped, and the persisted
  `source`/`license` for group management + ShareAlike.
  """
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food.IngredientPortion
  alias Mehungry.FoodData.UniToolsImporter

  @meta %{
    name: "UniTools World Recipes",
    version: "2.0.0",
    license: "CC BY-SA 4.0",
    attribution: "UniTools — theunitools.com",
    landing_page: "https://theunitools.com/en/data"
  }

  # A decoded recipe as Decoder.decode/1 would hand it over.
  defp recipe(ingredients, overrides \\ %{}) do
    Map.merge(
      %{
        index: 1,
        title: "Spaghetti carbonara",
        native_name: "Spaghetti alla carbonara",
        summary: "Pasta from four ingredients.",
        category: "main",
        cuisine: "Italian cuisine",
        country: "IT",
        servings: 2,
        difficulty: 2,
        prep_minutes: 10,
        cook_minutes: 15,
        nutrition: %{"calories" => 690},
        ingredients: ingredients,
        directions: ["Boil the water.", "Crisp the guanciale."],
        raw: "{...}"
      },
      overrides
    )
  end

  defp description_portion(ingredient_id, description, gram_weight) do
    {:ok, p} =
      %IngredientPortion{}
      |> Ecto.Changeset.change(%{
        ingredient_id: ingredient_id,
        measurement_unit_id: nil,
        amount: 1.0,
        gram_weight: gram_weight,
        description: description
      })
      |> Mehungry.Repo.insert()

    p
  end

  setup do
    user = Mehungry.AccountsFixtures.user_fixture()
    measurement_unit_fixture(%{name: "grams"})
    spaghetti = ingredient_fixture(%{name: "Spaghetti", food_class: "Foundation"})
    %{user: user, spaghetti: spaghetti}
  end

  describe "build_recipe_attrs/3 — mapping" do
    test "maps title, licence/attribution, source, times, cuisine, steps", ctx do
      assert {:ok, attrs, _} =
               UniToolsImporter.build_recipe_attrs(recipe([]), @meta, ctx.user.id)

      assert attrs.title == "Spaghetti carbonara"
      assert attrs.language_name == "En"
      assert attrs.private == true
      assert attrs.user_id == ctx.user.id
      assert attrs.difficulty == 2
      assert attrs.servings == 2
      assert attrs.cousine == "Italian cuisine"

      # Real times from the dataset (lower == upper).
      assert attrs.cooking_time_lower_limit == 15
      assert attrs.cooking_time_upper_limit == 15
      assert attrs.preperation_time_lower_limit == 10

      # Provenance + ShareAlike licence.
      assert attrs.source == "unitools"
      assert attrs.license == "CC BY-SA 4.0"
      assert attrs.author == "UniTools — theunitools.com (CC BY-SA 4.0)"
      assert attrs.original_url == "https://theunitools.com/en/data"

      # No photo imported (per-image licences not vetted).
      refute Map.has_key?(attrs, :image_url)

      # summary + native note + credit seed the description.
      assert attrs.description =~ "Pasta from four ingredients."
      assert attrs.description =~ "Spaghetti alla carbonara"
      assert attrs.description =~ "CC BY-SA 4.0"

      # directions → one step each (no sentence splitting).
      assert [%{index: 1, description: "Boil the water."} | _] = attrs.steps
      assert length(attrs.steps) == 2
    end
  end

  describe "build_recipe_attrs/3 — ingredient matching" do
    test "a structured gram ingredient resolves through the shared resolver", ctx do
      ingredients = [%{name: "spaghetti", quantity: 200.0, unit: "g", original: "200 g Spaghetti"}]

      assert {:ok, attrs, []} =
               UniToolsImporter.build_recipe_attrs(recipe(ingredients), @meta, ctx.user.id)

      assert [ri] = attrs.recipe_ingredients
      assert ri.ingredient_id == ctx.spaghetti.id
      assert ri.quantity == 200.0
      assert ri.ingredient_allias == "200 g Spaghetti"
      # grams → a measurement unit, encoded positively for the form dropdown.
      assert ri.unit_selection == ri.measurement_unit_id
    end

    test "matched and unmatched ingredients are partitioned", ctx do
      ingredients = [
        %{name: "spaghetti", quantity: 200.0, unit: "g", original: "200 g Spaghetti"},
        %{name: "quokkaberry", quantity: 2.0, unit: "g", original: "2 g quokkaberry"}
      ]

      assert {:ok, attrs, unmatched} =
               UniToolsImporter.build_recipe_attrs(recipe(ingredients), @meta, ctx.user.id)

      assert length(attrs.recipe_ingredients) == 1
      assert [%{name: "quokkaberry"}] = unmatched
    end

    test "a description-only portion unit encodes as the negated portion id", ctx do
      olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      description_portion(olive.id, "tbsp", 13.5)

      ingredients = [%{name: "olive oil", quantity: 2.0, unit: "tbsp", original: "2 tbsp olive oil"}]

      assert {:ok, attrs, []} =
               UniToolsImporter.build_recipe_attrs(recipe(ingredients), @meta, ctx.user.id)

      assert [ri] = attrs.recipe_ingredients
      assert ri.unit_selection == -ri.ingredient_portion_id
    end
  end

  describe "source + licence (persisted) + group management" do
    test "a saved UniTools recipe carries source/licence and is group-manageable", ctx do
      ingredients = [%{name: "spaghetti", quantity: 200.0, unit: "g", original: "200 g Spaghetti"}]

      {:ok, attrs, _} =
        UniToolsImporter.build_recipe_attrs(recipe(ingredients), @meta, ctx.user.id)

      assert {:ok, saved} = Mehungry.Food.create_recipe(attrs)
      assert saved.source == "unitools"
      assert saved.license == "CC BY-SA 4.0"
      assert saved.private == true

      assert Mehungry.Food.count_recipes_by_source("unitools") == 1
      assert {:ok, 1} = Mehungry.Food.delete_recipes_by_source("unitools")
      assert Mehungry.Food.count_recipes_by_source("unitools") == 0
    end
  end
end
