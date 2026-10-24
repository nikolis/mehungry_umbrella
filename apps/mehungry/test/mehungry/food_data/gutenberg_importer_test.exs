defmodule Mehungry.FoodData.GutenbergImporterTest do
  @moduledoc """
  Covers the DB-backed mapping + matching of the Gutenberg importer
  (`build_recipe_attrs/3`) — field mapping, public-domain attribution,
  free-text ingredient resolution, the `unit_selection` seeded for the review
  form, and the persisted `source` marker for group management.
  """
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food.IngredientPortion
  alias Mehungry.FoodData.GutenbergImporter

  @book %{
    id: "6385",
    title: "Simple Italian Cookery",
    author: "Antonia Isola",
    cuisine: "Italian",
    format: :heading
  }

  # A parsed recipe block as BookParser would hand it over.
  defp recipe(ingredient_lines, overrides \\ %{}) do
    Map.merge(
      %{
        index: 4,
        title: "BEEF SOUP STOCK",
        subtitle: "Brodo di Carne",
        ingredient_lines: ingredient_lines,
        directions: "Boil the beef and vegetables. Skim occasionally. Strain and serve.",
        raw: "BEEF SOUP STOCK\n..."
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
    olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
    %{user: user, olive: olive}
  end

  describe "build_recipe_attrs/3 — mapping" do
    test "maps title (title-cased), attribution, source, steps and description", ctx do
      assert {:ok, attrs, _} =
               GutenbergImporter.build_recipe_attrs(recipe([]), @book, ctx.user.id)

      # ALL-CAPS book title → Title Case for display.
      assert attrs.title == "Beef Soup Stock"
      assert attrs.language_name == "En"
      # Staged private until the admin curates + publishes it.
      assert attrs.private == true
      assert attrs.user_id == ctx.user.id
      assert attrs.difficulty == 1
      # Provenance marker so imports can be group-managed later.
      assert attrs.source == "gutenberg"

      # Public-domain credit: book + author in `author`, landing page in original_url.
      assert attrs.author =~ "Simple Italian Cookery by Antonia Isola"
      assert attrs.author =~ "public domain"
      assert attrs.original_url == "https://www.gutenberg.org/ebooks/6385"

      # Original-language subtitle seeds the description.
      assert attrs.description =~ "Brodo di Carne"

      # directions → sentence-sized steps.
      assert [%{index: 1, description: "Boil the beef and vegetables."} | _] = attrs.steps
      assert length(attrs.steps) == 3
    end
  end

  describe "build_recipe_attrs/3 — ingredient matching" do
    test "a free-text line resolves through the parser + shared resolver", ctx do
      description_portion(ctx.olive.id, "cup", 218.0)

      assert {:ok, attrs, []} =
               GutenbergImporter.build_recipe_attrs(
                 recipe(["1/2 cup olive oil"]),
                 @book,
                 ctx.user.id
               )

      assert [ri] = attrs.recipe_ingredients
      assert ri.ingredient_id == ctx.olive.id
      assert ri.quantity == 0.5
      assert ri.ingredient_allias == "1/2 cup olive oil"
      # A description-only portion encodes as the negated portion id for the form.
      assert ri.unit_selection == -ri.ingredient_portion_id
    end

    test "matched and unmatched lines are partitioned", ctx do
      description_portion(ctx.olive.id, "cup", 218.0)

      assert {:ok, attrs, unmatched} =
               GutenbergImporter.build_recipe_attrs(
                 recipe(["1 cup olive oil", "2 cups quokkaberry"]),
                 @book,
                 ctx.user.id
               )

      assert length(attrs.recipe_ingredients) == 1
      assert [%{name: "quokkaberry"}] = unmatched
    end

    test "always returns {:ok, attrs, unmatched} with no ingredient lines", ctx do
      # Numbered-prose books list ingredients inline; the recipe still imports
      # and the admin adds ingredients by hand — no {:error, _} short-circuit.
      assert {:ok, attrs, []} =
               GutenbergImporter.build_recipe_attrs(recipe([]), @book, ctx.user.id)

      assert attrs.recipe_ingredients == []
      assert attrs.title == "Beef Soup Stock"
    end
  end

  describe "source marker (persisted) + group management" do
    test "a saved Gutenberg recipe carries source: \"gutenberg\" and is group-manageable",
         ctx do
      description_portion(ctx.olive.id, "cup", 218.0)

      {:ok, attrs, _} =
        GutenbergImporter.build_recipe_attrs(recipe(["1 cup olive oil"]), @book, ctx.user.id)

      assert {:ok, saved} = Mehungry.Food.create_recipe(attrs)
      assert saved.source == "gutenberg"

      assert Mehungry.Food.count_recipes_by_source("gutenberg") == 1
      assert {:ok, 1} = Mehungry.Food.delete_recipes_by_source("gutenberg")
      assert Mehungry.Food.count_recipes_by_source("gutenberg") == 0
    end
  end
end
