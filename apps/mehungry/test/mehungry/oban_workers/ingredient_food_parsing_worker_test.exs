defmodule Mehungry.ObanWorkers.IngredientFoodParsingWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food

  alias Mehungry.Food.{
    FoodParsingRuns,
    Ingredient,
    IngredientParsedFood,
    ParsedFoods,
    ParserVocabularySeeder
  }

  alias Mehungry.FoodData.Usda.Parser.Pipeline
  alias Mehungry.ObanWorkers.IngredientFoodParsingWorker, as: Worker
  alias Mehungry.Repo

  setup do
    ParserVocabularySeeder.seed()
    :ok
  end

  defp usda_ingredient(name, fdc_id) do
    case Food.get_ingredient_by_name(name) do
      nil -> ingredient_fixture(%{name: name, fdc_id: fdc_id})
      existing -> existing |> Ecto.Changeset.change(fdc_id: fdc_id) |> Repo.update!()
    end
  end

  # Pre-existing fdc-backed ingredients in the shared test DB get a parse row
  # so the batch only picks up this test's fixtures.
  defp mark_all_parsed(opts) do
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

  test "parses the batch, updates progress, and re-enqueues itself" do
    carrot = usda_ingredient("Carrots, baby, raw", 200_001)
    daiquiri = usda_ingredient("Alcoholic beverage, daiquiri, canned", 200_002)
    mark_all_parsed(except: [carrot.id, daiquiri.id])

    {:ok, run} = ParsedFoods.enqueue_food_parsing()
    assert_enqueued(worker: Worker, args: %{"run_id" => run.id})

    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert %{canonical_food_text: "carrot", status: "candidate"} =
             Repo.get_by(IngredientParsedFood,
               ingredient_id: carrot.id,
               parser_version: Pipeline.version()
             )

    assert %{skip_reason: "not_food"} =
             Repo.get_by(IngredientParsedFood,
               ingredient_id: daiquiri.id,
               parser_version: Pipeline.version()
             )

    run = FoodParsingRuns.latest_run()
    assert run.status == "processing"
    assert run.processed == run.total

    # the chain continues until the batch comes back empty
    assert :ok = perform_job(Worker, %{"run_id" => run.id})
    assert FoodParsingRuns.latest_run().status == "completed"
  end

  test "already-parsed ingredients are excluded (idempotent retry)" do
    ingredient = usda_ingredient("Oil, corn", 200_003)
    mark_all_parsed(except: [ingredient.id])
    {:ok, _, :created} = ParsedFoods.parse_ingredient(ingredient)
    count_before = Repo.aggregate(IngredientParsedFood, :count)

    run = FoodParsingRuns.start_run()
    assert :ok = perform_job(Worker, %{"run_id" => run.id})

    assert Repo.aggregate(IngredientParsedFood, :count) == count_before
    assert FoodParsingRuns.latest_run().status == "completed"
  end
end
