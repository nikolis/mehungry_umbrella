defmodule Mehungry.Food.PortionTranslationTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, Localization, Recipe, RecipeIngredient}

  setup do
    ingredient = ingredient_fixture()
    unit = measurement_unit_fixture(%{name: "cup"})

    {:ok, free_text} =
      Food.create_ingredient_portion(%{
        ingredient_id: ingredient.id,
        description: "1 medium banana",
        gram_weight: 118.0
      })

    {:ok, with_unit} =
      Food.create_ingredient_portion(%{
        ingredient_id: ingredient.id,
        measurement_unit_id: unit.id,
        gram_weight: 240.0
      })

    %{ingredient: ingredient, unit: unit, free_text: free_text, with_unit: with_unit}
  end

  describe "upsert_portion_translation/4 + portion_display_names/2" do
    test "round-trips a translation under the ISO code", %{free_text: portion} do
      assert {:ok, _} =
               Food.upsert_portion_translation(portion.id, "el", "1 μέτρια μπανάνα", status: "verified")

      assert Food.portion_display_names([portion.id], "el") == %{portion.id => "1 μέτρια μπανάνα"}
    end

    test "re-upsert updates the same row (no duplicate)", %{free_text: portion} do
      Food.upsert_portion_translation(portion.id, "el", "πρώτο", status: "ai_draft")
      Food.upsert_portion_translation(portion.id, "el", "δεύτερο", status: "verified")

      assert Food.portion_display_names([portion.id], "el") == %{portion.id => "δεύτερο"}
    end

    test "source locale returns no overrides", %{free_text: portion} do
      Food.upsert_portion_translation(portion.id, "el", "1 μέτρια μπανάνα")
      assert Food.portion_display_names([portion.id], "en") == %{}
    end
  end

  describe "list_portion_translation_pairs/2" do
    test "lists only unit-less meaningful portions, paired with their translation",
         %{ingredient: ingredient, free_text: free_text, with_unit: with_unit} do
      Food.upsert_portion_translation(free_text.id, "el", "1 μέτρια μπανάνα")

      pairs = Food.list_portion_translation_pairs(ingredient.id, "el")

      ids = Enum.map(pairs, & &1.portion.id)
      assert free_text.id in ids
      refute with_unit.id in ids

      pair = Enum.find(pairs, &(&1.portion.id == free_text.id))
      assert pair.translation.description == "1 μέτρια μπανάνα"
    end
  end

  describe "build_unit_options/2" do
    test "overlays the translated label on a unit-less portion, leaves unit-bearing untouched",
         %{ingredient: ingredient, free_text: free_text} do
      Food.upsert_portion_translation(free_text.id, "el", "1 μέτρια μπανάνα")

      portions = Food.get_measurement_unit_portions_for_ingredient(ingredient.id)
      options = Food.build_unit_options(portions, "el")

      # The label's quantity is stripped (IngredientPortion.strip_amount/1).
      free_text_opt = Enum.find(options, &(&1.ingredient_portion_id == free_text.id))
      assert free_text_opt.label == "μέτρια μπανάνα"

      # The unit-bearing portion still labels from its measurement unit.
      assert Enum.any?(options, &(&1.label == "cup"))
    end

    test "source locale keeps the original English description",
         %{ingredient: ingredient, free_text: free_text} do
      Food.upsert_portion_translation(free_text.id, "el", "1 μέτρια μπανάνα")

      portions = Food.get_measurement_unit_portions_for_ingredient(ingredient.id)
      options = Food.build_unit_options(portions, "en")

      # Quantity stripped from the original English description too.
      free_text_opt = Enum.find(options, &(&1.ingredient_portion_id == free_text.id))
      assert free_text_opt.label == "medium banana"
    end
  end

  describe "ingredient_ids_with_untranslated_portions/1 + count" do
    test "lists ingredients with a missing unit-less portion translation, excludes fully-done ones",
         %{ingredient: ingredient, free_text: free_text} do
      # Before translating: the ingredient shows up as having untranslated portions.
      assert ingredient.id in Food.ingredient_ids_with_untranslated_portions("el")
      assert Food.count_ingredients_with_untranslated_portions("el") >= 1

      # After translating its only free-text portion, it drops out.
      Food.upsert_portion_translation(free_text.id, "el", "1 μέτρια μπανάνα")

      refute ingredient.id in Food.ingredient_ids_with_untranslated_portions("el")
    end

    test "a unit-bearing-only ingredient never shows up", %{unit: unit} do
      other = ingredient_fixture()

      {:ok, _} =
        Food.create_ingredient_portion(%{
          ingredient_id: other.id,
          measurement_unit_id: unit.id,
          gram_weight: 100.0
        })

      refute other.id in Food.ingredient_ids_with_untranslated_portions("el")
    end
  end

  describe "ResourceTranslationWorker portions-only run" do
    use Oban.Testing, repo: Mehungry.Repo

    alias Mehungry.ObanWorkers.ResourceTranslationWorker
    alias Mehungry.Food.IngredientTranslation

    test "never creates or touches the base ingredient translation",
         %{ingredient: ingredient} do
      # A portions-only run is for already-translated ingredients: it must leave
      # the base name/description translation alone (here: create none at all).
      assert :ok =
               perform_job(ResourceTranslationWorker, %{
                 "resource" => "ingredients",
                 "language" => "el",
                 "ids" => [ingredient.id],
                 "portions_only" => true
               })

      refute Repo.get_by(IngredientTranslation, ingredient_id: ingredient.id, language_name: "el")
    end

    test "leaves an already-translated portion untouched (no AI re-draft)",
         %{ingredient: ingredient, free_text: portion} do
      {:ok, verified} =
        Food.upsert_portion_translation(portion.id, "el", "χειροκίνητο", status: "verified")

      assert :ok =
               perform_job(ResourceTranslationWorker, %{
                 "resource" => "ingredients",
                 "language" => "el",
                 "ids" => [ingredient.id],
                 "portions_only" => true
               })

      pairs = Food.list_portion_translation_pairs(ingredient.id, "el")
      pair = Enum.find(pairs, &(&1.portion.id == portion.id))
      assert pair.translation.id == verified.id
      assert pair.translation.description == "χειροκίνητο"
      assert pair.translation.status == "verified"
    end
  end

  describe "localize_recipe_ingredients/2 (recipe render)" do
    test "overlays the translated portion description onto a recipe ingredient",
         %{ingredient: ingredient, free_text: portion} do
      Food.upsert_portion_translation(portion.id, "el", "1 μέτρια μπανάνα")

      recipe = %Recipe{
        recipe_ingredients: [
          %RecipeIngredient{
            quantity: 1.0,
            ingredient_id: ingredient.id,
            ingredient_portion_id: portion.id,
            measurement_unit: nil,
            ingredient_portion: portion,
            ingredient: %Ingredient{id: ingredient.id, name: ingredient.name}
          }
        ]
      }

      localized = Localization.localize_recipe_ingredients(recipe, "el")
      [ri] = localized.recipe_ingredients

      # Rendered label has its quantity stripped (IngredientPortion.strip_amount/1).
      assert RecipeIngredient.unit_label(ri) == "μέτρια μπανάνα"
    end
  end
end
