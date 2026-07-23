defmodule Mehungry.ObanWorkers.TaxonomyClassificationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  import Ecto.Query

  alias Mehungry.Food.Taxonomies
  alias Mehungry.ObanWorkers.TaxonomyClassificationWorker
  alias Mehungry.Repo
  alias Mehungry.Food.{Ingredient, IngredientTaxonomyNode}

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :taxonomy_classifier_stub) end)

    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Bio", slug: "bio-#{System.unique_integer([:positive])}"})

    {:ok, meat} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: taxonomy.id})
    {:ok, beef} = Taxonomies.create_node(%{name: "Beef", slug: "beef", taxonomy_id: taxonomy.id, parent_id: meat.id})

    {:ok, other} =
      Taxonomies.create_node(%{name: "Other", slug: "other-unclassified", taxonomy_id: taxonomy.id})

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
    ing = ingredient_fixture(%{name: "beef steak"})

    stub(fn ingredients, _leaves ->
      send(self(), {:classified, length(ingredients)})
      rows = Enum.map(ingredients, &%{ingredient_id: &1.id, taxonomy_node_id: ctx.beef.id, confidence: 0.9})
      {:ok, rows}
    end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    assert_received {:classified, n} when n >= 1

    mapping = Repo.get_by!(IngredientTaxonomyNode, ingredient_id: ing.id)
    assert mapping.taxonomy_node_id == ctx.beef.id
    assert mapping.source == "ai"
    assert mapping.confidence == 0.9
    refute mapping.reviewed

    assert_enqueued(
      worker: TaxonomyClassificationWorker,
      args: %{"taxonomy_id" => ctx.taxonomy.id}
    )
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
    ingredient_fixture(%{name: "unusable thing"})

    # Classifier returns nothing usable for a non-empty batch.
    stub(fn _ingredients, _leaves -> {:ok, []} end)

    assert :ok =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    refute_enqueued(worker: TaxonomyClassificationWorker)
  end

  test "classifier error returns {:error, _} for Oban retry", ctx do
    ingredient_fixture(%{name: "boom"})

    stub(fn _ingredients, _leaves -> {:error, "api down"} end)

    assert {:error, "api down"} =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    refute_enqueued(worker: TaxonomyClassificationWorker)
  end
end
