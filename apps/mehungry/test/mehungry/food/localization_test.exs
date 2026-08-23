defmodule Mehungry.Food.LocalizationTest do
  use Mehungry.DataCase

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures

  alias Mehungry.Food.Localization
  alias Mehungry.Food.{Recipe, Step}
  alias Mehungry.AI.Bot.RecipeTranslation

  describe "apply_recipe_translation/2 — translated steps (batch translation read path)" do
    defp recipe_with_steps do
      %Recipe{
        title: "Boiled Pasta",
        description: "Simple pasta.",
        steps: [
          %Step{index: 0, title: "Boil", description: "Boil water"},
          %Step{index: 1, title: "Cook", description: "Add pasta"}
        ]
      }
    end

    test "overlays each step description by index, preserving step titles" do
      translation = %RecipeTranslation{
        title: "Βραστά Ζυμαρικά",
        description: "Απλά ζυμαρικά.",
        steps: [
          %{"index" => 0, "description" => "Βράστε νερό"},
          %{"index" => 1, "description" => "Προσθέστε τα ζυμαρικά"}
        ]
      }

      result = Localization.apply_recipe_translation(recipe_with_steps(), translation)

      assert result.title == "Βραστά Ζυμαρικά"
      assert result.description == "Απλά ζυμαρικά."
      assert Enum.map(result.steps, & &1.description) == ["Βράστε νερό", "Προσθέστε τα ζυμαρικά"]
      # Step titles are not translated — they must survive untouched.
      assert Enum.map(result.steps, & &1.title) == ["Boil", "Cook"]
    end

    test "a step with no (or blank) translation keeps its base description" do
      translation = %RecipeTranslation{
        title: "Βραστά Ζυμαρικά",
        steps: [
          %{"index" => 0, "description" => "Βράστε νερό"},
          %{"index" => 1, "description" => ""}
        ]
      }

      result = Localization.apply_recipe_translation(recipe_with_steps(), translation)

      assert Enum.map(result.steps, & &1.description) == ["Βράστε νερό", "Add pasta"]
    end

    test "no steps in the translation leaves the base steps intact" do
      translation = %RecipeTranslation{title: "Βραστά Ζυμαρικά", steps: []}
      result = Localization.apply_recipe_translation(recipe_with_steps(), translation)
      assert Enum.map(result.steps, & &1.description) == ["Boil water", "Add pasta"]
    end
  end

  describe "load_recipe_translations_map/2 — locale codes" do
    setup do
      unless Mehungry.Languages.get_language_by_name("el") do
        {:ok, _} = Mehungry.Languages.create_language(%{name: "el"})
      end

      :ok
    end

    defp insert_recipe_translation(recipe_id, code, title) do
      {:ok, _} =
        %RecipeTranslation{}
        |> RecipeTranslation.changeset(%{
          recipe_id: recipe_id,
          language_name: code,
          title: title
        })
        |> Repo.insert()
    end

    test "finds a legacy \"Gr\" translation via the \"el\" locale, preferring canonical \"el\"" do
      recipe = recipe_fixture(user_fixture(), %{title: "Pasta"})

      # Legacy-only row is found under the "el" locale (data_codes ["el", "Gr"]).
      insert_recipe_translation(recipe.id, "Gr", "Ζυμαρικά (Gr)")
      map = Localization.load_recipe_translations_map([recipe.id], "el")
      assert map[recipe.id].title == "Ζυμαρικά (Gr)"

      # When both an ISO and a legacy row exist, the canonical "el" row wins.
      insert_recipe_translation(recipe.id, "el", "Ζυμαρικά (el)")
      map2 = Localization.load_recipe_translations_map([recipe.id], "el")
      assert map2[recipe.id].title == "Ζυμαρικά (el)"
    end
  end
end
