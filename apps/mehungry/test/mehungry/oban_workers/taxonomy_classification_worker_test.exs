defmodule Mehungry.ObanWorkers.TaxonomyClassificationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  import Ecto.Query

  alias Mehungry.Food.Taxonomies
  alias Mehungry.Food.TaxonomyClassificationRuns
  alias Mehungry.ObanWorkers.TaxonomyClassificationWorker
  alias Mehungry.Repo
  alias Mehungry.Food.{Ingredient, IngredientTaxonomyNode, TaxonomyClassificationRun}

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :taxonomy_classifier_stub) end)

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{
        name: "Bio",
        slug: "bio-#{System.unique_integer([:positive])}"
      })

    {:ok, meat} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: taxonomy.id})

    {:ok, beef} =
      Taxonomies.create_node(%{
        name: "Beef",
        slug: "beef",
        taxonomy_id: taxonomy.id,
        parent_id: meat.id
      })

    {:ok, other} =
      Taxonomies.create_node(%{
        name: "Other",
        slug: "other-unclassified",
        taxonomy_id: taxonomy.id
      })

    %{taxonomy: taxonomy, beef: beef, other: other}
  end

  defp stub(fun), do: Application.put_env(:mehungry, :taxonomy_classifier_stub, fun)

  # Mark every existing ingredient as classified under `node_id` for this
  # taxonomy, so the worker sees an empty batch. Keeps the test independent of
  # whatever ingredient rows the DB happens to hold (seeded locally, empty in CI).
  defp classify_all_ingredients(node_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      from(i in Ingredient, select: i.id)
      |> Repo.all()
      |> Enum.map(
        &%{
          ingredient_id: &1,
          taxonomy_node_id: node_id,
          source: "manual",
          reviewed: false,
          inserted_at: now,
          updated_at: now
        }
      )

    Repo.insert_all(IngredientTaxonomyNode, rows,
      on_conflict: :nothing,
      conflict_target: [:ingredient_id, :taxonomy_node_id]
    )
  end

  test "writes ai rows with confidence and re-enqueues on progress", ctx do
    # Pre-classify everything else so the batch is exactly our new ingredient,
    # independent of how many rows the DB holds or their physical order.
    classify_all_ingredients(ctx.other.id)
    ing = ingredient_fixture(%{name: "beef steak", fdc_id: 111_111})

    stub(fn ingredients, _leaves ->
      send(self(), {:classified, Enum.map(ingredients, & &1.id)})

      rows =
        Enum.map(
          ingredients,
          &%{ingredient_id: &1.id, taxonomy_node_id: ctx.beef.id, confidence: 0.5}
        )

      {:ok, rows}
    end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    assert_received {:classified, [classified_id]}
    assert classified_id == ing.id

    mapping = Repo.get_by!(IngredientTaxonomyNode, ingredient_id: ing.id)
    assert mapping.taxonomy_node_id == ctx.beef.id
    assert mapping.source == "ai"
    assert mapping.confidence == 0.5
    # Below the 0.80 auto-confirm threshold, so it still needs human review.
    refute mapping.reviewed

    assert_enqueued(
      worker: TaxonomyClassificationWorker,
      args: %{"taxonomy_id" => ctx.taxonomy.id}
    )
  end

  test "auto-confirms mappings above the 0.80 confidence threshold", ctx do
    classify_all_ingredients(ctx.other.id)
    high = ingredient_fixture(%{name: "obvious beef", fdc_id: 666_666})

    stub(fn ingredients, _leaves ->
      {:ok,
       Enum.map(
         ingredients,
         &%{ingredient_id: &1.id, taxonomy_node_id: ctx.beef.id, confidence: 0.95}
       )}
    end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    mapping = Repo.get_by!(IngredientTaxonomyNode, ingredient_id: high.id)
    assert mapping.confidence == 0.95
    # High confidence skips the review queue.
    assert mapping.reviewed
  end

  test "a nil confidence is never auto-confirmed", ctx do
    classify_all_ingredients(ctx.other.id)
    unscored = ingredient_fixture(%{name: "mystery meat", fdc_id: 777_777})

    stub(fn ingredients, _leaves ->
      {:ok, Enum.map(ingredients, &%{ingredient_id: &1.id, taxonomy_node_id: ctx.beef.id})}
    end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    mapping = Repo.get_by!(IngredientTaxonomyNode, ingredient_id: unscored.id)
    assert is_nil(mapping.confidence)
    refute mapping.reviewed
  end

  test "empty batch (all classified) terminates without calling classifier or enqueueing", ctx do
    ingredient_fixture(%{name: "already beef"})
    classify_all_ingredients(ctx.beef.id)

    stub(fn _ingredients, _leaves ->
      flunk("classifier should not be called when nothing is unclassified")
    end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    refute_enqueued(worker: TaxonomyClassificationWorker)
  end

  test "zero-insert non-empty batch halts (loop guard)", ctx do
    ingredient_fixture(%{name: "unusable thing", fdc_id: 222_222})

    # Classifier returns nothing usable for a non-empty batch.
    stub(fn _ingredients, _leaves -> {:ok, []} end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    refute_enqueued(worker: TaxonomyClassificationWorker)
  end

  test "classifier error returns {:error, _} for Oban retry", ctx do
    ingredient_fixture(%{name: "boom", fdc_id: 333_333})

    stub(fn _ingredients, _leaves -> {:error, "api down"} end)

    assert {:error, "api down"} =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    refute_enqueued(worker: TaxonomyClassificationWorker)
  end

  test "skips ingredients without a proper fdc_id", ctx do
    # Neutralize any pre-seeded fdc-backed rows so the only unclassified
    # ingredients are the two ineligible ones we add below.
    classify_all_ingredients(ctx.other.id)

    # No fdc_id (nil) and a non-positive fdc_id are both ineligible; the batch is
    # empty, so the classifier is never called and the worker just terminates.
    ingredient_fixture(%{name: "no fdc"})
    ingredient_fixture(%{name: "zero fdc", fdc_id: 0})

    stub(fn _ingredients, _leaves ->
      flunk("classifier should not be called for ingredients without a proper fdc_id")
    end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    refute_enqueued(worker: TaxonomyClassificationWorker)
  end

  describe "run tracking" do
    test "marks the run processing then completed on an empty batch", ctx do
      ingredient_fixture(%{name: "already beef"})
      classify_all_ingredients(ctx.beef.id)
      run = TaxonomyClassificationRuns.start_run(ctx.taxonomy.id)

      assert :ok =
               perform_job(TaxonomyClassificationWorker, %{
                 "taxonomy_id" => ctx.taxonomy.id,
                 "run_id" => run.id
               })

      reloaded = Repo.get!(TaxonomyClassificationRun, run.id)
      assert reloaded.status == "completed"
      assert reloaded.completed_at
    end

    test "updates progress and keeps the run processing across a re-enqueue", ctx do
      classify_all_ingredients(ctx.other.id)
      ingredient_fixture(%{name: "beef steak", fdc_id: 444_444})
      run = TaxonomyClassificationRuns.start_run(ctx.taxonomy.id)

      Phoenix.PubSub.subscribe(
        Mehungry.PubSub,
        TaxonomyClassificationRuns.topic(ctx.taxonomy.id)
      )

      stub(fn ingredients, _leaves ->
        {:ok,
         Enum.map(
           ingredients,
           &%{ingredient_id: &1.id, taxonomy_node_id: ctx.beef.id, confidence: 0.9}
         )}
      end)

      assert :ok =
               perform_job(TaxonomyClassificationWorker, %{
                 "taxonomy_id" => ctx.taxonomy.id,
                 "run_id" => run.id
               })

      assert_received {:classification_run, %TaxonomyClassificationRun{status: "processing"}}

      reloaded = Repo.get!(TaxonomyClassificationRun, run.id)
      assert reloaded.status == "processing"

      # The chained batch carries the run_id forward.
      assert_enqueued(
        worker: TaxonomyClassificationWorker,
        args: %{"taxonomy_id" => ctx.taxonomy.id, "run_id" => run.id}
      )
    end

    test "marks the run failed on a classifier error", ctx do
      ingredient_fixture(%{name: "boom", fdc_id: 555_555})
      run = TaxonomyClassificationRuns.start_run(ctx.taxonomy.id)

      stub(fn _ingredients, _leaves -> {:error, "api down"} end)

      assert {:error, "api down"} =
               perform_job(TaxonomyClassificationWorker, %{
                 "taxonomy_id" => ctx.taxonomy.id,
                 "run_id" => run.id
               })

      reloaded = Repo.get!(TaxonomyClassificationRun, run.id)
      assert reloaded.status == "failed"
      assert reloaded.error =~ "api down"
    end
  end
end
