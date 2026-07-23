defmodule Mehungry.ObanWorkers.TaxonomyClassificationWorkerTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food.{IngredientTaxonomyNode, Taxonomies}
  alias Mehungry.ObanWorkers.TaxonomyClassificationWorker
  alias Mehungry.Repo

  setup do
    on_exit(fn -> Application.delete_env(:mehungry, :taxonomy_classifier_stub) end)

    {:ok, taxonomy} = Taxonomies.create_taxonomy(%{name: "Bio", slug: "bio-nutritional"})
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
        name: "Other / Unclassified",
        slug: "other-unclassified",
        taxonomy_id: taxonomy.id
      })

    %{taxonomy: taxonomy, beef: beef, other: other}
  end

  test "writes AI mappings and re-enqueues while work remains", ctx do
    ingredient = ingredient_fixture(%{name: "Beef, ground, raw"})
    test_pid = self()

    Application.put_env(:mehungry, :taxonomy_classifier_stub, fn ingredients, leaves ->
      send(test_pid, {:classified, ingredients, leaves})

      {:ok,
       Map.new(ingredients, fn %{id: id} -> {id, %{slug: "beef", confidence: 0.9}} end)}
    end)

    assert :ok = perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})

    assert_received {:classified, ingredients, leaves}
    assert Enum.any?(ingredients, &(&1.id == ingredient.id))
    leaf_slugs = Enum.map(leaves, & &1.slug) |> Enum.sort()
    assert leaf_slugs == ["beef", "other-unclassified"]

    mapping = Repo.get_by!(IngredientTaxonomyNode, ingredient_id: ingredient.id)
    assert mapping.taxonomy_node_id == ctx.beef.id
    assert mapping.source == "ai"
    assert mapping.confidence == 0.9
    refute mapping.reviewed

    assert_enqueued(
      worker: TaxonomyClassificationWorker,
      args: %{taxonomy_id: ctx.taxonomy.id}
    )
  end

  test "completes without re-enqueue when everything is classified", ctx do
    ingredient = ingredient_fixture()
    {:ok, _} = Taxonomies.attach_ingredient(ingredient.id, ctx.beef.id, %{source: "manual"})

    Application.put_env(:mehungry, :taxonomy_classifier_stub, fn _ingredients, _leaves ->
      flunk("classifier should not be called when nothing is unclassified")
    end)

    assert :ok = perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})
    refute_enqueued(worker: TaxonomyClassificationWorker)
  end

  test "stops the chain when a batch yields no usable assignments", ctx do
    ingredient_fixture(%{name: "Mystery substance"})

    Application.put_env(:mehungry, :taxonomy_classifier_stub, fn _ingredients, _leaves ->
      {:ok, %{}}
    end)

    assert :ok = perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})
    refute_enqueued(worker: TaxonomyClassificationWorker)
    assert Repo.aggregate(IngredientTaxonomyNode, :count) == 0
  end

  test "returns an error for Oban retries when the classifier fails", ctx do
    ingredient_fixture()

    Application.put_env(:mehungry, :taxonomy_classifier_stub, fn _ingredients, _leaves ->
      {:error, :api_down}
    end)

    assert {:error, :api_down} =
             perform_job(TaxonomyClassificationWorker, %{"taxonomy_id" => ctx.taxonomy.id})
  end
end
