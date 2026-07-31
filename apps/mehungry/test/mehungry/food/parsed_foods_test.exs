defmodule Mehungry.Food.ParsedFoodsTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Food

  alias Mehungry.Food.{
    CanonicalFood,
    Ingredient,
    IngredientParsedFood,
    ParsedFoods,
    ParserVocabularySeeder
  }

  alias Mehungry.FoodData.Usda.Parser.Pipeline
  alias Mehungry.Repo

  setup do
    ParserVocabularySeeder.seed()
    :ok
  end

  # The shared test DB may contain committed ingredients with real USDA names;
  # reuse them (updating fdc_id inside the sandbox) instead of colliding on the
  # unique name index.
  defp usda_ingredient(name, fdc_id) do
    case Food.get_ingredient_by_name(name) do
      nil -> ingredient_fixture(%{name: name, fdc_id: fdc_id})
      existing -> existing |> Ecto.Changeset.change(fdc_id: fdc_id) |> Repo.update!()
    end
  end

  # Neutralizes pre-existing fdc-backed ingredients for progress/batch
  # assertions: give each a (rejected) parse at the current version.
  defp mark_all_parsed(opts \\ []) do
    naive = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    except = Keyword.get(opts, :except, [])

    rows =
      Repo.all(
        from(i in Ingredient,
          where: not is_nil(i.fdc_id) and i.fdc_id > 0 and i.id not in ^except,
          select: i.id
        )
      )
      |> Enum.map(
        &%{
          ingredient_id: &1,
          canonical_food_text: "preexisting",
          parser_version: Pipeline.version(),
          status: "rejected",
          inserted_at: naive,
          updated_at: naive
        }
      )

    Repo.insert_all(IngredientParsedFood, rows)
  end

  describe "parse_ingredient/1" do
    test "stores a structured candidate row" do
      ingredient = usda_ingredient("Carrots, baby, raw", 100_001)

      assert {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert parsed.canonical_food_text == "carrot"
      assert is_integer(parsed.canonical_food_id)
      assert parsed.harvest_stage == "baby"
      assert parsed.processing == ["raw"]
      assert parsed.packaging == "na"
      assert parsed.confidence == 1.0
      assert parsed.status == "candidate"
      assert parsed.parser_version == Pipeline.version()
      assert [%{"stage" => _} | _] = parsed.trace
    end

    test "stores part and dismemberment for meat cuts" do
      ingredient = usda_ingredient("Beef, loin, T-bone steak, raw", 100_015)

      assert {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert parsed.canonical_food_text == "beef"
      assert parsed.part == "loin"
      assert parsed.dismemberment == "t bone steak"
    end

    test "stores bone_state, portion, grade and fat for a full meat cut" do
      ingredient =
        usda_ingredient(
          "Beef, loin, top loin steak, boneless, separable lean only, trimmed to 1/8\" fat, choice, raw",
          100_016
        )

      assert {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert parsed.canonical_food_text == "beef"
      assert parsed.part == "loin"
      assert parsed.dismemberment == "top loin steak"
      assert parsed.bone_state == "boneless"
      assert parsed.portion == ["separable lean only"]
      assert parsed.grade == "choice"
      assert parsed.fat == "trimmed to 1/8 fat"
    end

    test "skips prepared/composite dishes" do
      ingredient = usda_ingredient("White bread, commercial", 100_017)

      assert {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert parsed.skip_reason == "prepared_dish"
      assert parsed.canonical_food_text == nil
    end

    test "stores skipped descriptions in the same table" do
      ingredient = usda_ingredient("Alcoholic beverage, daiquiri, canned", 100_002)

      assert {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert parsed.skip_reason == "not_food"
      assert parsed.canonical_food_text == nil
    end

    test "is find-or-create on (ingredient, parser_version)" do
      ingredient = usda_ingredient("Oil, corn", 100_003)

      assert {:ok, first, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert {:ok, second, :exists} = ParsedFoods.parse_ingredient(ingredient)
      assert first.id == second.id

      assert Repo.aggregate(
               from(p in IngredientParsedFood, where: p.ingredient_id == ^ingredient.id),
               :count
             ) == 1
    end
  end

  describe "review workflow" do
    test "update_parsed_candidate edits semantic fields while candidate" do
      ingredient = usda_ingredient("Frobnitz, canned", 100_004)
      {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)

      assert {:ok, updated} =
               ParsedFoods.update_parsed_candidate(parsed.id, %{
                 canonical_food_text: "dragon fruit",
                 processing: ["dried"],
                 status: "verified"
               })

      assert updated.canonical_food_text == "dragon fruit"
      assert updated.processing == ["dried"]
      # non-editable fields are ignored
      assert updated.status == "candidate"
    end

    test "update_parsed_candidate refuses non-candidate rows" do
      ingredient = usda_ingredient("Oil, corn", 100_005)
      {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)
      {:ok, _} = ParsedFoods.verify_parsed_food(parsed.id)

      assert {:error, :not_editable} =
               ParsedFoods.update_parsed_candidate(parsed.id, %{canonical_food_text: "x"})
    end

    test "verify links (find-or-creating) the canonical food and supersedes prior verified" do
      ingredient = usda_ingredient("Carrots, baby, raw", 100_006)
      {:ok, first, :created} = ParsedFoods.parse_ingredient(ingredient)
      {:ok, verified_first} = ParsedFoods.verify_parsed_food(first.id)
      assert verified_first.status == "verified"
      assert verified_first.verified_at != nil

      # a second (edited) candidate for the same ingredient, e.g. after a version bump
      {:ok, second, :created} =
        ParsedFoods.add_parsed_candidate(%{
          ingredient_id: ingredient.id,
          canonical_food_text: "heirloom carrot",
          parser_version: "9.9.9",
          status: "candidate"
        })

      {:ok, verified_second} = ParsedFoods.verify_parsed_food(second.id)

      assert verified_second.status == "verified"
      assert %CanonicalFood{} = Repo.get_by(CanonicalFood, name: "heirloom carrot")

      assert verified_second.canonical_food_id ==
               Repo.get_by(CanonicalFood, name: "heirloom carrot").id

      assert %{status: "superseded", superseded_by_id: superseded_by} =
               Repo.get(IngredientParsedFood, first.id)

      assert superseded_by == second.id
    end

    test "verify refuses skipped rows" do
      ingredient = usda_ingredient("Alcoholic beverage, wine", 100_007)
      {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)

      assert {:error, :skipped_row} = ParsedFoods.verify_parsed_food(parsed.id)
    end

    test "reject keeps the row for history" do
      ingredient = usda_ingredient("Oil, corn", 100_008)
      {:ok, parsed, :created} = ParsedFoods.parse_ingredient(ingredient)

      assert {:ok, %{status: "rejected"}} = ParsedFoods.reject_parsed_food(parsed.id)
      assert ParsedFoods.list_pending_parse_review() == []
    end
  end

  describe "review queries" do
    test "pending review lists current-version candidates, lowest confidence first" do
      confident = usda_ingredient("Oil, corn", 100_009)
      shaky = usda_ingredient("Frobnitz, canned", 100_010)
      {:ok, _, :created} = ParsedFoods.parse_ingredient(confident)
      {:ok, _, :created} = ParsedFoods.parse_ingredient(shaky)

      assert [first, second] = ParsedFoods.list_pending_parse_review()
      assert first.ingredient.id == shaky.id
      assert second.ingredient.id == confident.id
    end

    test "skipped parses are listed separately" do
      ingredient = usda_ingredient("Alcoholic beverage, rum", 100_011)
      {:ok, _, :created} = ParsedFoods.parse_ingredient(ingredient)

      assert [skipped] = ParsedFoods.list_skipped_parses()
      assert skipped.skip_reason == "not_food"
      assert ParsedFoods.list_pending_parse_review() == []
    end
  end

  describe "progress + batching" do
    test "progress counts fdc-backed coverage at the current version" do
      parsed = usda_ingredient("Oil, corn", 100_012)
      unparsed = usda_ingredient("Carrots, baby, raw", 100_013)
      _non_fdc = ingredient_fixture(%{})
      mark_all_parsed(except: [parsed.id, unparsed.id])

      %{processed: p0, total: t0} = ParsedFoods.parsing_progress()
      assert p0 == t0 - 2

      {:ok, _, :created} = ParsedFoods.parse_ingredient(parsed)

      assert ParsedFoods.parsing_progress() == %{processed: p0 + 1, total: t0}
    end

    test "unparsed batch excludes rows only at the current version" do
      ingredient = usda_ingredient("Oil, corn", 100_014)
      mark_all_parsed(except: [ingredient.id])

      {:ok, _, :created} =
        ParsedFoods.add_parsed_candidate(%{
          ingredient_id: ingredient.id,
          canonical_food_text: "corn",
          parser_version: "0.0.1",
          status: "candidate"
        })

      assert [%{id: id}] = ParsedFoods.list_unparsed_ingredients(1000)
      assert id == ingredient.id

      {:ok, _, :created} = ParsedFoods.parse_ingredient(ingredient)
      assert ParsedFoods.list_unparsed_ingredients(1000) == []
    end
  end
end
