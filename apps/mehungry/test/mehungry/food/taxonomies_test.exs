defmodule Mehungry.Food.TaxonomiesTest do
  use Mehungry.DataCase
  use Oban.Testing, repo: Mehungry.Repo

  import Mehungry.FoodFixtures

  alias Mehungry.Food
  alias Mehungry.Food.Taxonomies
  alias Mehungry.ObanWorkers.TaxonomyClassificationWorker

  defp taxonomy_fixture do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{
        name: "Bio",
        slug: "bio-#{System.unique_integer([:positive])}"
      })

    taxonomy
  end

  defp node_fixture(taxonomy, slug, parent \\ nil) do
    {:ok, node} =
      Taxonomies.create_node(%{
        name: slug,
        slug: slug,
        taxonomy_id: taxonomy.id,
        parent_id: parent && parent.id
      })

    node
  end

  # Food → Meat → Red Meat → {Beef, Lamb}; Meat → Poultry → Chicken
  defp tree_fixture do
    taxonomy = taxonomy_fixture()
    food = node_fixture(taxonomy, "food")
    meat = node_fixture(taxonomy, "meat", food)
    red_meat = node_fixture(taxonomy, "red-meat", meat)
    beef = node_fixture(taxonomy, "beef", red_meat)
    lamb = node_fixture(taxonomy, "lamb", red_meat)
    poultry = node_fixture(taxonomy, "poultry", meat)
    chicken = node_fixture(taxonomy, "chicken", poultry)

    %{
      taxonomy: taxonomy,
      food: food,
      meat: meat,
      red_meat: red_meat,
      beef: beef,
      lamb: lamb,
      poultry: poultry,
      chicken: chicken
    }
  end

  describe "subtree queries across levels" do
    setup do
      t = tree_fixture()

      beef_ing = ingredient_fixture(%{name: "beef steak"})
      lamb_ing = ingredient_fixture(%{name: "lamb chop"})
      chicken_ing = ingredient_fixture(%{name: "chicken breast"})

      Taxonomies.attach_ingredient(beef_ing.id, t.beef.id, %{source: "manual"})
      Taxonomies.attach_ingredient(lamb_ing.id, t.lamb.id, %{source: "manual"})
      Taxonomies.attach_ingredient(chicken_ing.id, t.chicken.id, %{source: "manual"})

      Map.merge(t, %{beef_ing: beef_ing, lamb_ing: lamb_ing, chicken_ing: chicken_ing})
    end

    test "subtree_node_ids includes the node and all descendants", %{meat: meat} = ctx do
      ids = Taxonomies.subtree_node_ids(meat.id)

      assert meat.id in ids
      assert ctx.red_meat.id in ids
      assert ctx.beef.id in ids
      assert ctx.chicken.id in ids
      refute ctx.food.id in ids
    end

    test "red_meat rolls up beef + lamb but not chicken", ctx do
      names =
        ctx.red_meat.id
        |> Taxonomies.list_ingredients_under_node()
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["beef steak", "lamb chop"]
    end

    test "meat rolls up beef, lamb and chicken (≥3 levels)", ctx do
      names =
        ctx.meat.id
        |> Taxonomies.list_ingredients_under_node()
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert names == ["beef steak", "chicken breast", "lamb chop"]
    end

    test "sibling isolation: poultry excludes red-meat ingredients", ctx do
      names =
        ctx.poultry.id
        |> Taxonomies.list_ingredients_under_node()
        |> Enum.map(& &1.name)

      assert names == ["chicken breast"]
    end
  end

  describe "build_tree/1" do
    test "returns nested maps with rolled-up counts in accordion shape" do
      t = tree_fixture()

      beef_ing = ingredient_fixture(%{name: "beef a"})
      lamb_ing = ingredient_fixture(%{name: "lamb a"})
      Taxonomies.attach_ingredient(beef_ing.id, t.beef.id, %{source: "manual"})
      Taxonomies.attach_ingredient(lamb_ing.id, t.lamb.id, %{source: "manual"})

      [root] = Food.build_tree(t.taxonomy.id)

      assert root.name == "food"
      assert root.measurement_unit == "foods"
      # food → meat rolls up both red-meat leaves
      assert root.amount == 2

      meat = hd(root.children)
      assert meat.slug == "meat"
      assert meat.amount == 2

      red_meat = Enum.find(meat.children, &(&1.slug == "red-meat"))
      assert red_meat.amount == 2
      beef = Enum.find(red_meat.children, &(&1.slug == "beef"))
      assert beef.amount == 1
      assert beef.children == []
    end
  end

  describe "constraints" do
    test "duplicate slug within a taxonomy errors (incl. two roots — PG14 NULL case)" do
      taxonomy = taxonomy_fixture()
      node_fixture(taxonomy, "root")

      assert {:error, changeset} =
               Taxonomies.create_node(%{name: "Root 2", slug: "root", taxonomy_id: taxonomy.id})

      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "same slug allowed in a different taxonomy" do
      t1 = taxonomy_fixture()
      t2 = taxonomy_fixture()
      node_fixture(t1, "meat")

      assert {:ok, _} =
               Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: t2.id})
    end

    test "attach_ingredient is idempotent per (ingredient, node)" do
      t = tree_fixture()
      ing = ingredient_fixture(%{name: "dup steak"})

      assert {:ok, _} = Taxonomies.attach_ingredient(ing.id, t.beef.id, %{source: "manual"})

      assert {:error, changeset} =
               Taxonomies.attach_ingredient(ing.id, t.beef.id, %{source: "ai", confidence: 0.5})

      assert errors_on(changeset)[:ingredient_id]
    end
  end

  describe "leaves" do
    test "list_leaf_nodes returns only childless nodes" do
      t = tree_fixture()

      slugs = t.taxonomy.id |> Taxonomies.list_leaf_nodes() |> Enum.map(& &1.slug) |> Enum.sort()

      assert slugs == ["beef", "chicken", "lamb"]
    end

    test "list_leaves_with_paths gives full ancestor path" do
      t = tree_fixture()

      paths = Taxonomies.list_leaves_with_paths(t.taxonomy.id)
      beef = Enum.find(paths, &(&1.slug == "beef"))

      assert beef.path == "food > meat > red-meat > beef"
    end
  end

  describe "review_mapping/2" do
    setup do
      t = tree_fixture()
      ing = ingredient_fixture(%{name: "review steak"})

      {:ok, mapping} =
        Taxonomies.attach_ingredient(ing.id, t.beef.id, %{source: "ai", confidence: 0.3})

      Map.merge(t, %{mapping: mapping})
    end

    test ":confirm marks reviewed", %{mapping: mapping} do
      assert {:ok, updated} = Taxonomies.review_mapping(mapping.id, :confirm)
      assert updated.reviewed
      assert updated.source == "ai"
    end

    test "{:override, node_id} moves to node as manual, reviewed, no confidence", ctx do
      assert {:ok, updated} =
               Taxonomies.review_mapping(ctx.mapping.id, {:override, ctx.lamb.id})

      assert updated.taxonomy_node_id == ctx.lamb.id
      assert updated.source == "manual"
      assert updated.reviewed
      assert is_nil(updated.confidence)
    end
  end

  describe "list_pending_review/2" do
    test "returns unreviewed rows lowest-confidence first" do
      t = tree_fixture()
      a = ingredient_fixture(%{name: "ing a"})
      b = ingredient_fixture(%{name: "ing b"})
      c = ingredient_fixture(%{name: "ing c"})

      Taxonomies.attach_ingredient(a.id, t.beef.id, %{source: "ai", confidence: 0.9})
      Taxonomies.attach_ingredient(b.id, t.lamb.id, %{source: "ai", confidence: 0.2})

      {:ok, reviewed} =
        Taxonomies.attach_ingredient(c.id, t.chicken.id, %{source: "ai", confidence: 0.1})

      Taxonomies.review_mapping(reviewed.id, :confirm)

      rows = Taxonomies.list_pending_review(t.taxonomy.id)

      confidences = Enum.map(rows, & &1.confidence)
      assert confidences == [0.2, 0.9]
      # preloads available
      assert Enum.all?(rows, &(&1.ingredient != nil and &1.taxonomy_node != nil))
    end
  end

  describe "classification_progress/1" do
    test "counts distinct classified ingredients against the total" do
      t = tree_fixture()
      a = ingredient_fixture(%{name: "ing a"})
      b = ingredient_fixture(%{name: "ing b"})
      _c = ingredient_fixture(%{name: "ing c"})

      Taxonomies.attach_ingredient(a.id, t.beef.id, %{source: "ai", confidence: 0.9})
      # attaching the same ingredient to a second node still counts once
      Taxonomies.attach_ingredient(a.id, t.lamb.id, %{source: "manual"})
      Taxonomies.attach_ingredient(b.id, t.chicken.id, %{source: "ai", confidence: 0.2})

      progress = Taxonomies.classification_progress(t.taxonomy.id)

      # Only a and b are attached in this taxonomy (a counted once across two nodes).
      assert progress.classified == 2
      # total reflects every ingredient row, not just this taxonomy's.
      assert progress.total == Mehungry.Repo.aggregate(Mehungry.Food.Ingredient, :count)
      assert progress.total >= 3
    end
  end

  describe "enqueue_classification/1" do
    test "inserts a TaxonomyClassificationWorker job for the taxonomy" do
      t = taxonomy_fixture()

      assert {:ok, _job} = Taxonomies.enqueue_classification(t.id)

      assert_enqueued(
        worker: TaxonomyClassificationWorker,
        args: %{"taxonomy_id" => t.id}
      )
    end
  end
end
