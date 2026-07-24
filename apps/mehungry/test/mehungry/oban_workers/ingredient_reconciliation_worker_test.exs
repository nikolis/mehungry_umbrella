# Canned USDA record, in the nested-map format FdcClient.fetch_food/1 produces
# and FoodParser.reconcile_ingredient/2 expects. `fetch_food/1` now returns a
# `{:ok, attrs, meta}` triple where meta carries the API's remaining quota.
defmodule Mehungry.ObanWorkers.ReconFixtures do
  def salt_attrs do
    %{
      "description" => "Salt, table",
      "dataType" => "Foundation",
      "foodClass" => "FinalFood",
      "fdcId" => 999_999,
      "ndbNumber" => 2047,
      "publicationDate" => "4/1/2019",
      "nutrientConversionFactors" => [],
      "foodCategory" => %{"description" => "Spices and Herbs"},
      "foodPortions" => [
        %{
          "modifier" => "g",
          "gramWeight" => 100.0,
          "amount" => 1.0,
          "value" => 100.0,
          "id" => 1,
          "sequenceNumber" => 1,
          "minYearAcquired" => nil
        }
      ],
      "foodNutrients" => [
        %{
          "amount" => 38_758.0,
          "median" => nil,
          "dataPoints" => nil,
          "type" => "FoodNutrient",
          "nutrient" => %{
            "id" => 1093,
            "name" => "Sodium, Na",
            "number" => "307",
            "rank" => 5800,
            "unitName" => "mg"
          }
        }
      ]
    }
  end
end

defmodule Mehungry.ObanWorkers.IngredientReconciliationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.ObanWorkers.IngredientReconciliationWorker
  alias Mehungry.ObanWorkers.ReconFixtures
  alias Mehungry.Food.Ingredient
  alias Mehungry.Repo

  defmodule OkStub do
    def fetch_food(999_999), do: {:ok, ReconFixtures.salt_attrs(), %{remaining: 100}}
    def fetch_food(_other), do: {:error, "no FDC results"}
  end

  defmodule ErrorStub do
    def fetch_food(_fdc_id), do: {:error, "FDC lookup failed"}
  end

  # Every lookup reports a hard rate-limit: the worker should snooze, not bump.
  defmodule RateLimitedStub do
    def fetch_food(_fdc_id), do: {:error, {:rate_limited, 30}}
  end

  # Reconciles fine but the API's remaining quota is exhausted, so the worker
  # should bump the handled row and then snooze proactively.
  defmodule LowRemainingStub do
    def fetch_food(_fdc_id), do: {:ok, ReconFixtures.salt_attrs(), %{remaining: 1}}
  end

  # The dev DB may hold rows; drop everything to version 0 so this test is
  # independent of whatever ingredients already exist (seeded locally, empty CI).
  defp reset_versions do
    Repo.update_all(Ingredient, set: [version: 0])
  end

  defp use_fdc_client(module) do
    Application.put_env(:mehungry, :fdc_client, module)
    on_exit(fn -> Application.delete_env(:mehungry, :fdc_client) end)
  end

  test "corrects an ingredient from its fdc_id, bumps version to target, and re-enqueues" do
    reset_versions()
    use_fdc_client(OkStub)

    ing = ingredient_fixture(%{name: "salt", fdc_id: 999_999, data_type: nil})

    assert :ok = perform_job(IngredientReconciliationWorker, %{})

    reloaded =
      Ingredient
      |> Repo.get!(ing.id)
      |> Repo.preload([:ingredient_portions, ingredient_nutrients: :nutrient])

    # USDA metadata + nutritional payload corrected in place...
    assert reloaded.data_type == "Foundation"
    assert reloaded.version == IngredientReconciliationWorker.target_version()
    assert [portion] = reloaded.ingredient_portions
    assert portion.gram_weight == 100.0
    assert [ing_nutrient] = reloaded.ingredient_nutrients
    assert ing_nutrient.nutrient.name == "Sodium, Na"
    assert ing_nutrient.amount == 38_758.0
    # ...but the name is never rewritten by a reconciliation pass.
    assert reloaded.name == "salt"

    assert_enqueued(worker: IngredientReconciliationWorker)
  end

  test "rows without an fdc_id terminate: version bumps without a USDA lookup" do
    reset_versions()
    use_fdc_client(OkStub)

    ing = ingredient_fixture(%{name: "mystery food", fdc_id: nil})

    assert :ok = perform_job(IngredientReconciliationWorker, %{})

    reloaded = Repo.get!(Ingredient, ing.id)
    assert reloaded.version == IngredientReconciliationWorker.target_version()
  end

  test "a failed USDA lookup still bumps version so the pass terminates" do
    reset_versions()
    use_fdc_client(ErrorStub)

    ing = ingredient_fixture(%{name: "salt", fdc_id: 999_999})

    assert :ok = perform_job(IngredientReconciliationWorker, %{})

    reloaded = Repo.get!(Ingredient, ing.id)
    assert reloaded.version == IngredientReconciliationWorker.target_version()
  end

  test "empty batch (all at target version) terminates without re-enqueueing" do
    Repo.update_all(Ingredient, set: [version: IngredientReconciliationWorker.target_version()])

    assert :ok = perform_job(IngredientReconciliationWorker, %{})

    refute_enqueued(worker: IngredientReconciliationWorker)
  end

  test "a rate-limited lookup snoozes the job and leaves the row unbumped" do
    reset_versions()
    use_fdc_client(RateLimitedStub)

    # Newest id is processed first, so this freshly-inserted row is the one that
    # hits the rate-limit and halts the batch.
    ing = ingredient_fixture(%{name: "salt", fdc_id: 999_999})

    assert {:snooze, 30} = perform_job(IngredientReconciliationWorker, %{})

    reloaded = Repo.get!(Ingredient, ing.id)
    # Left behind for a retry rather than silently marked done.
    assert reloaded.version == 0
    # Snooze reschedules the same job; no fresh batch is enqueued.
    refute_enqueued(worker: IngredientReconciliationWorker)
  end

  test "low remaining quota bumps the handled row then snoozes proactively" do
    reset_versions()
    use_fdc_client(LowRemainingStub)

    ing = ingredient_fixture(%{name: "salt", fdc_id: 999_999})

    assert {:snooze, seconds} = perform_job(IngredientReconciliationWorker, %{})
    assert seconds > 0

    reloaded = Repo.get!(Ingredient, ing.id)
    # The row that succeeded before the quota check is bumped...
    assert reloaded.version == IngredientReconciliationWorker.target_version()
    # ...and the batch snoozes instead of enqueueing the next one.
    refute_enqueued(worker: IngredientReconciliationWorker)
  end
end
