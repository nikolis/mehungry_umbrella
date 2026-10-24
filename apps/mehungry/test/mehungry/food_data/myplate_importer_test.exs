defmodule Mehungry.FoodData.MyPlateImporterTest do
  @moduledoc """
  Covers the DB-backed mapping + matching of the MyPlate importer
  (`build_recipe_attrs/2`) — field mapping, attribution, free-text ingredient
  resolution, and the `unit_selection` seeded for the review form's unit dropdown.
  """
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food.IngredientPortion
  alias Mehungry.FoodData.MyPlateImporter

  # A minimal MyPlate /recipes/{slug} payload. `ingredients` is the list of
  # %{"text" => _, "note" => _} maps the caller varies per test.
  defp myplate_data(ingredients, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Zucchini Bread",
        "yield" => "16 servings",
        "serving_size" => "1",
        "description" => "A tasty quick bread.",
        "directions" => "Preheat oven to 325. Mix well. Bake 50 minutes.",
        "image_url" => "https://img.example/zucchini-bread.jpg",
        "source_url" => "https://www.myplate.gov/recipes/zucchini-bread",
        "recipe_url" => "https://myplate.food/recipes/zucchini-bread",
        "contributor" => "Washington State University Extension",
        "ingredients" => ingredients
      },
      overrides
    )
  end

  defp ing(text, note \\ nil), do: %{"text" => text, "note" => note}

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

  describe "build_recipe_attrs/2 — mapping" do
    setup do
      user = Mehungry.AccountsFixtures.user_fixture()
      measurement_unit_fixture(%{name: "grams"})
      olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      description_portion(olive.id, "cup", 218.0)
      %{user: user, olive: olive}
    end

    test "maps scalar fields, attribution, servings and steps", ctx do
      data = myplate_data([ing("1 cup olive oil")])

      assert {:ok, attrs, _unmatched} = MyPlateImporter.build_recipe_attrs(data, ctx.user.id)

      assert attrs.title == "Zucchini Bread"
      assert attrs.servings == 16
      assert attrs.image_url == "https://img.example/zucchini-bread.jpg"
      assert attrs.original_url == "https://www.myplate.gov/recipes/zucchini-bread"
      assert attrs.language_name == "En"
      assert attrs.private == false
      assert attrs.user_id == ctx.user.id
      assert attrs.difficulty == 1
      # Provenance marker so imports can be group-managed later.
      assert attrs.source == "myplate"

      # Attribution: contributor + public-domain credit in `author`.
      assert attrs.author =~ "Washington State University Extension"
      assert attrs.author =~ "USDA MyPlate (public domain)"

      # directions → sentence-sized steps.
      assert [%{index: 1, description: "Preheat oven to 325."} | _] = attrs.steps
      assert length(attrs.steps) == 3
    end

    test "parses servings from a bare serving_size when yield is absent", ctx do
      data = myplate_data([ing("1 cup olive oil")], %{"yield" => nil, "serving_size" => "8"})
      assert {:ok, %{servings: 8}, _} = MyPlateImporter.build_recipe_attrs(data, ctx.user.id)
    end

    test "attribution falls back to a generic USDA credit with no contributor", ctx do
      data = myplate_data([ing("1 cup olive oil")], %{"contributor" => nil})
      assert {:ok, %{author: author}, _} = MyPlateImporter.build_recipe_attrs(data, ctx.user.id)
      assert author == "USDA MyPlate Kitchen (public domain)"
    end
  end

  describe "build_recipe_attrs/2 — ingredient matching" do
    setup do
      user = Mehungry.AccountsFixtures.user_fixture()
      measurement_unit_fixture(%{name: "grams"})
      olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      %{user: user, olive: olive}
    end

    test "a free-text line resolves through the parser + shared resolver", ctx do
      description_portion(ctx.olive.id, "cup", 218.0)
      data = myplate_data([ing("1/2 cup olive oil")])

      assert {:ok, attrs, []} = MyPlateImporter.build_recipe_attrs(data, ctx.user.id)
      assert [ri] = attrs.recipe_ingredients
      assert ri.ingredient_id == ctx.olive.id
      assert ri.quantity == 0.5
      assert ri.ingredient_allias == "1/2 cup olive oil"
      # unit_selection is seeded so the review form's dropdown shows the choice:
      # a description-only portion encodes as the negated portion id.
      assert ri.unit_selection == -ri.ingredient_portion_id
    end

    test "matched and unmatched lines are partitioned", ctx do
      description_portion(ctx.olive.id, "cup", 218.0)
      data = myplate_data([ing("1 cup olive oil"), ing("2 cups quokkaberry")])

      assert {:ok, attrs, unmatched} = MyPlateImporter.build_recipe_attrs(data, ctx.user.id)
      assert length(attrs.recipe_ingredients) == 1
      assert [%{name: "quokkaberry"}] = unmatched
    end

    test "always returns {:ok, attrs, unmatched} even when nothing matches", ctx do
      # The review form must still render (with 0 matched + the unmatched list)
      # so the admin can fix lines by hand — no {:error, _} short-circuit.
      data = myplate_data([ing("2 cups quokkaberry")])

      assert {:ok, attrs, unmatched} = MyPlateImporter.build_recipe_attrs(data, ctx.user.id)
      assert attrs.recipe_ingredients == []
      assert [%{name: "quokkaberry"}] = unmatched
      assert attrs.title == "Zucchini Bread"
    end
  end

  describe "source marker (persisted) + group management" do
    setup do
      user = Mehungry.AccountsFixtures.user_fixture()
      measurement_unit_fixture(%{name: "grams"})
      olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      description_portion(olive.id, "cup", 218.0)
      %{user: user}
    end

    test "a saved MyPlate recipe carries source: \"myplate\" and is group-countable/deletable",
         ctx do
      {:ok, attrs, _} =
        MyPlateImporter.build_recipe_attrs(myplate_data([ing("1 cup olive oil")]), ctx.user.id)

      assert {:ok, recipe} = Mehungry.Food.create_recipe(attrs)
      assert recipe.source == "myplate"

      assert Mehungry.Food.count_recipes_by_source("myplate") == 1
      assert {:ok, 1} = Mehungry.Food.delete_recipes_by_source("myplate")
      assert Mehungry.Food.count_recipes_by_source("myplate") == 0
    end
  end
end
