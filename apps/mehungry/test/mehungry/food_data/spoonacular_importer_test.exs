defmodule Mehungry.FoodData.SpoonacularImporterTest do
  @moduledoc """
  Covers the pure, DB-backed parsing + matching core of the Spoonacular
  importer (`build_recipe_attrs/2`) and the shared relevance-filtered ingredient
  resolution it leans on (`IngredientSearch.best_match/1`). The HTTP layer
  (`fetch_recipe`/`search_recipes`) is thin and not exercised here; its only
  non-trivial behaviour — the missing-key guard — is asserted via the public
  entry points.
  """
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food.IngredientSearch
  alias Mehungry.Food.IngredientPortion
  alias Mehungry.FoodData.SpoonacularImporter

  # A minimal Spoonacular /information payload. `extended` is the list of
  # extendedIngredients maps the caller wants to vary per test.
  defp spoon_data(extended, overrides \\ %{}) do
    Map.merge(
      %{
        "title" => "Test Dish",
        "servings" => 4,
        "readyInMinutes" => 25,
        "image" => "http://img.example/dish.jpg",
        "sourceUrl" => "http://src.example/dish",
        "summary" => "A <b>tasty</b> dish &amp; a quick one.",
        "cuisines" => ["Greek"],
        "nutrition" => %{
          "nutrients" => [
            %{"name" => "Calories", "amount" => 320.5, "unit" => "kcal"},
            %{"name" => "Protein", "amount" => 12.0, "unit" => "g"}
          ]
        },
        "analyzedInstructions" => [
          %{"steps" => [%{"number" => 1, "step" => "Chop."}, %{"number" => 2, "step" => "Cook."}]}
        ],
        "extendedIngredients" => extended
      },
      overrides
    )
  end

  defp ing(name, amount, unit, original \\ nil) do
    %{
      "name" => name,
      "amount" => amount,
      "unit" => unit,
      "original" => original || "#{amount} #{unit} #{name}"
    }
  end

  # A description-only USDA portion (measurement_unit_id: nil, free-text label +
  # gram weight) — the shape 99.6% of real portions take.
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

  # find_gram_unit/0 resolves to the first gram-family row that exists ("g" /
  # "gram" / "grams"), so assert the *kind* of unit, not a specific fixture id.
  defp assert_gram_unit(mu_id) do
    unit = Mehungry.Repo.get!(Mehungry.Food.MeasurementUnit, mu_id)
    assert String.downcase(unit.name) in ~w(g gr gram grams grammar)
  end

  describe "IngredientSearch.best_match/1 (shared relevance gate)" do
    setup do
      olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      %{olive: olive}
    end

    test "returns the relevant ingredient for a close name", %{olive: olive} do
      assert %{id: id} = IngredientSearch.best_match("olive oil")
      assert id == olive.id
    end

    test "returns nil when the only candidates are not relevant" do
      # "saffron" shares no first-word similarity with "Olive oil", so the
      # relevance filter rejects the incidental fuzzy hit instead of returning it.
      assert IngredientSearch.best_match("saffron") == nil
    end

    test "rejects partial/processed variants the query didn't ask for" do
      # Distinctive stem so the assertion is insensitive to any seeded egg rows.
      ingredient_fixture(%{name: "Zzqegg, white, dried", food_class: "Foundation"})
      whole = ingredient_fixture(%{name: "Zzqegg, whole, raw", food_class: "Foundation"})

      assert %{id: id} = IngredientSearch.best_match("zzqegg")
      assert id == whole.id
    end
  end

  describe "build_recipe_attrs/2 — matching" do
    setup do
      user = Mehungry.AccountsFixtures.user_fixture()
      grams = measurement_unit_fixture(%{name: "grams"})
      olive = ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      %{user: user, grams: grams, olive: olive}
    end

    test "builds a recipe_ingredient for a matched ingredient + gram unit", ctx do
      data = spoon_data([ing("olive oil", 30.0, "grams", "30g olive oil")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [ri] = attrs.recipe_ingredients

      assert ri.ingredient_id == ctx.olive.id
      assert_gram_unit(ri.measurement_unit_id)
      assert ri.quantity == 30.0
      assert ri.ingredient_allias == "30g olive oil"
    end

    test "unmatched ingredient → :ingredient_not_found", ctx do
      data = spoon_data([ing("quokkaberry", 2.0, "grams")])

      assert {:error, _} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
    end

    test "unresolvable unit with no portion, mass or gram metric → unmatched", ctx do
      data = spoon_data([ing("olive oil", 1.0, "fluxograms")])

      assert {:error, _} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
    end

    test "#1: a matching description-only portion resolves to that portion (verbatim qty)", ctx do
      # "Olive oil" has a "cup" USDA description portion; 0.5 cup stays 0.5 and
      # points at the portion (whose gram_weight drives nutrition downstream).
      portion = description_portion(ctx.olive.id, "cup", 218.0)
      data = spoon_data([ing("olive oil", 0.5, "cup")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [ri] = attrs.recipe_ingredients
      assert ri.ingredient_portion_id == portion.id
      assert ri.measurement_unit_id == nil
      assert ri.quantity == 0.5
    end

    test "#1: tablespoon matches a 'tbsp chopped' style description portion", ctx do
      portion = description_portion(ctx.olive.id, "tbsp chopped", 10.0)
      data = spoon_data([ing("olive oil", 2.0, "tablespoons")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [%{ingredient_portion_id: pid}] = attrs.recipe_ingredients
      assert pid == portion.id
    end

    test "#1: empty/piece unit matches a 'medium' description portion", ctx do
      portion = description_portion(ctx.olive.id, "medium (2-1/2\" dia)", 110.0)
      data = spoon_data([ing("olive oil", 1.0, "")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [%{ingredient_portion_id: pid}] = attrs.recipe_ingredients
      assert pid == portion.id
    end

    test "#1: prefers the most generic portion label (cup over cup, chopped)", ctx do
      _chopped = description_portion(ctx.olive.id, "cup, chopped", 160.0)
      plain = description_portion(ctx.olive.id, "cup", 218.0)
      data = spoon_data([ing("olive oil", 1.0, "cups")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [%{ingredient_portion_id: pid}] = attrs.recipe_ingredients
      assert pid == plain.id
    end

    test "#3: ounces convert deterministically to grams (28.3495 g/oz)", ctx do
      data = spoon_data([ing("olive oil", 2.0, "oz")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [%{measurement_unit_id: mu_id, quantity: q}] = attrs.recipe_ingredients
      assert_gram_unit(mu_id)
      assert_in_delta q, 56.699, 0.01
    end

    test "falls back to grams via measures.metric when nothing else resolves", ctx do
      ing = %{
        "name" => "olive oil",
        "amount" => 0.5,
        "unit" => "cup",
        "original" => "1/2 cup olive oil",
        "measures" => %{"metric" => %{"amount" => 108.0, "unitShort" => "g"}}
      }

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(spoon_data([ing]), ctx.user.id)
      assert [%{measurement_unit_id: mu_id, quantity: 108.0}] = attrs.recipe_ingredients
      assert_gram_unit(mu_id)
    end

    test "no portion, no mass unit, no gram metric → stays unmatched", ctx do
      ing = %{
        "name" => "olive oil",
        "amount" => 0.5,
        "unit" => "cup",
        "original" => "1/2 cup olive oil",
        "measures" => %{"metric" => %{"amount" => 120.0, "unitShort" => "ml"}}
      }

      assert {:error, _} = SpoonacularImporter.build_recipe_attrs(spoon_data([ing]), ctx.user.id)
    end

    test "#2: prefers a lower-ranked whole food that HAS the portion over the top processed match", ctx do
      # "Zzonion dip" out-ranks "Zzonions, raw" on word similarity but has no
      # portions; the raw onion carries a "cup" portion, so for a cup measurement
      # the importer should pick the raw onion.
      _dip = ingredient_fixture(%{name: "Zzonion dip, light", food_class: "Survey (FNDDS)"})
      raw = ingredient_fixture(%{name: "Zzonions, raw", food_class: "SR Legacy"})
      portion = description_portion(raw.id, "cup, chopped", 160.0)

      data = spoon_data([ing("zzonion", 1.0, "cup")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert [ri] = attrs.recipe_ingredients
      assert ri.ingredient_id == raw.id
      assert ri.ingredient_portion_id == portion.id
    end

    test "matched and unmatched ingredients are partitioned", ctx do
      data =
        spoon_data([
          ing("olive oil", 30.0, "grams"),
          ing("quokkaberry", 2.0, "grams")
        ])

      assert {:ok, attrs, unmatched} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert length(attrs.recipe_ingredients) == 1
      assert [%{name: "quokkaberry", reason: :ingredient_not_found}] = unmatched
    end

    test "returns {:error, _} when nothing matches", ctx do
      data = spoon_data([ing("quokkaberry", 2.0, "grams")])
      assert {:error, msg} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert msg =~ "no ingredients"
    end

    test "blank ingredient names are skipped entirely", ctx do
      data = spoon_data([ing("olive oil", 30.0, "grams"), ing("", 1.0, "grams")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)
      assert length(attrs.recipe_ingredients) == 1
    end
  end

  describe "build_recipe_attrs/2 — parsing" do
    setup do
      user = Mehungry.AccountsFixtures.user_fixture()
      measurement_unit_fixture(%{name: "grams"})
      ingredient_fixture(%{name: "Olive oil", food_class: "Foundation"})
      %{user: user}
    end

    test "maps scalar fields, strips HTML, and extracts steps + nutrients", ctx do
      data = spoon_data([ing("olive oil", 30.0, "grams")])

      assert {:ok, attrs, []} = SpoonacularImporter.build_recipe_attrs(data, ctx.user.id)

      assert attrs.title == "Test Dish"
      assert attrs.servings == 4
      assert attrs.cousine == "Greek"
      assert attrs.image_url == "http://img.example/dish.jpg"
      assert attrs.original_url == "http://src.example/dish"
      assert attrs.language_name == "En"
      assert attrs.user_id == ctx.user.id

      # summary HTML tags + entities stripped
      assert attrs.description == "A tasty dish & a quick one."

      # analyzedInstructions → ordered steps
      assert [%{index: 1, description: "Chop."}, %{index: 2, description: "Cook."}] = attrs.steps

      # nutrition.nutrients → keyed map
      assert attrs.nutrients["Calories"] == %{amount: 320.5, unit: "kcal"}
    end

    test "difficulty is inferred from readyInMinutes", ctx do
      quick = spoon_data([ing("olive oil", 1.0, "grams")], %{"readyInMinutes" => 20})
      medium = spoon_data([ing("olive oil", 1.0, "grams")], %{"readyInMinutes" => 50})
      hard = spoon_data([ing("olive oil", 1.0, "grams")], %{"readyInMinutes" => 90})

      assert {:ok, %{difficulty: 1}, _} = SpoonacularImporter.build_recipe_attrs(quick, ctx.user.id)
      assert {:ok, %{difficulty: 2}, _} = SpoonacularImporter.build_recipe_attrs(medium, ctx.user.id)
      assert {:ok, %{difficulty: 3}, _} = SpoonacularImporter.build_recipe_attrs(hard, ctx.user.id)
    end
  end
end
