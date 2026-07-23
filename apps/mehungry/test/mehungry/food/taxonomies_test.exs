defmodule Mehungry.Food.TaxonomiesTest do
  use Mehungry.DataCase

  alias Mehungry.Food.Taxonomies
  alias Mehungry.FoodFixtures

  defp taxonomy_fixture do
    {:ok, taxonomy} =
      Taxonomies.create_taxonomy(%{name: "Biological / Nutritional", slug: "bio-nutritional"})

    taxonomy
  end

  defp node_fixture(taxonomy, attrs) do
    {:ok, node} =
      attrs
      |> Map.put(:taxonomy_id, taxonomy.id)
      |> Taxonomies.create_node()

    node
  end

  # Food > Meat > Red Meat > {Beef, Lamb}
  #             > Poultry  > {Chicken}
  defp seed_meat_tree(taxonomy) do
    food = node_fixture(taxonomy, %{name: "Food", slug: "food"})
    meat = node_fixture(taxonomy, %{name: "Meat", slug: "meat", parent_id: food.id})
    red_meat = node_fixture(taxonomy, %{name: "Red Meat", slug: "red-meat", parent_id: meat.id})
    poultry = node_fixture(taxonomy, %{name: "Poultry", slug: "poultry", parent_id: meat.id})
    beef = node_fixture(taxonomy, %{name: "Beef", slug: "beef", parent_id: red_meat.id})
    lamb = node_fixture(taxonomy, %{name: "Lamb", slug: "lamb", parent_id: red_meat.id})
    chicken = node_fixture(taxonomy, %{name: "Chicken", slug: "chicken", parent_id: poultry.id})

    %{
      food: food,
      meat: meat,
      red_meat: red_meat,
      poultry: poultry,
      beef: beef,
      lamb: lamb,
      chicken: chicken
    }
  end

  describe "node constraints" do
    test "duplicate slug within a taxonomy is rejected, including for two roots" do
      taxonomy = taxonomy_fixture()
      node_fixture(taxonomy, %{name: "Meat", slug: "meat"})

      assert {:error, changeset} =
               Taxonomies.create_node(%{name: "Meat 2", slug: "meat", taxonomy_id: taxonomy.id})

      assert %{taxonomy_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "the same slug is allowed across taxonomies" do
      taxonomy = taxonomy_fixture()
      {:ok, other} = Taxonomies.create_taxonomy(%{name: "Culinary", slug: "culinary"})

      node_fixture(taxonomy, %{name: "Meat", slug: "meat"})
      assert {:ok, _} = Taxonomies.create_node(%{name: "Meat", slug: "meat", taxonomy_id: other.id})
    end
  end

  describe "subtree queries" do
    test "list_ingredients_under_node/1 traverses the full subtree" do
      taxonomy = taxonomy_fixture()
      nodes = seed_meat_tree(taxonomy)

      beef_ing = FoodFixtures.ingredient_fixture(%{name: "Beef, ground, raw"})
      lamb_ing = FoodFixtures.ingredient_fixture(%{name: "Lamb, leg, raw"})
      chicken_ing = FoodFixtures.ingredient_fixture(%{name: "Chicken, breast, raw"})

      {:ok, _} = Taxonomies.attach_ingredient(beef_ing.id, nodes.beef.id, %{source: "manual"})
      {:ok, _} = Taxonomies.attach_ingredient(lamb_ing.id, nodes.lamb.id, %{source: "manual"})

      {:ok, _} =
        Taxonomies.attach_ingredient(chicken_ing.id, nodes.chicken.id, %{source: "manual"})

      red_meat_ids = Taxonomies.list_ingredients_under_node(nodes.red_meat.id) |> ids()
      assert red_meat_ids == Enum.sort([beef_ing.id, lamb_ing.id])

      meat_ids = Taxonomies.list_ingredients_under_node(nodes.meat.id) |> ids()
      assert meat_ids == Enum.sort([beef_ing.id, lamb_ing.id, chicken_ing.id])

      poultry_ids = Taxonomies.list_ingredients_under_node(nodes.poultry.id) |> ids()
      assert poultry_ids == [chicken_ing.id]
    end

    test "subtree_node_ids/1 includes the node itself and all descendants" do
      taxonomy = taxonomy_fixture()
      nodes = seed_meat_tree(taxonomy)

      assert Enum.sort(Taxonomies.subtree_node_ids(nodes.red_meat.id)) ==
               Enum.sort([nodes.red_meat.id, nodes.beef.id, nodes.lamb.id])

      assert Taxonomies.subtree_node_ids(nodes.chicken.id) == [nodes.chicken.id]
    end
  end

  describe "build_tree/1" do
    test "returns nested maps with rolled-up counts in the accordion shape" do
      taxonomy = taxonomy_fixture()
      nodes = seed_meat_tree(taxonomy)

      beef_ing = FoodFixtures.ingredient_fixture(%{name: "Beef, chuck, raw"})
      chicken_ing = FoodFixtures.ingredient_fixture(%{name: "Chicken, thigh, raw"})

      {:ok, _} = Taxonomies.attach_ingredient(beef_ing.id, nodes.beef.id, %{source: "manual"})

      {:ok, _} =
        Taxonomies.attach_ingredient(chicken_ing.id, nodes.chicken.id, %{source: "manual"})

      assert [%{name: "Food", slug: "food", measurement_unit: "foods", amount: 2} = food] =
               Taxonomies.build_tree(taxonomy.id)

      assert [%{name: "Meat", amount: 2, children: meat_children}] = food.children

      red_meat = Enum.find(meat_children, &(&1.slug == "red-meat"))
      poultry = Enum.find(meat_children, &(&1.slug == "poultry"))

      assert red_meat.amount == 1
      assert [%{name: "Beef", amount: 1}, %{name: "Lamb", amount: 0}] = red_meat.children
      assert poultry.amount == 1
    end
  end

  describe "leaf helpers" do
    test "list_leaf_nodes/1 and list_leaf_paths/1 return only childless nodes" do
      taxonomy = taxonomy_fixture()
      nodes = seed_meat_tree(taxonomy)

      leaf_ids = Taxonomies.list_leaf_nodes(taxonomy.id) |> Enum.map(& &1.id) |> Enum.sort()
      assert leaf_ids == Enum.sort([nodes.beef.id, nodes.lamb.id, nodes.chicken.id])

      paths = Taxonomies.list_leaf_paths(taxonomy.id)
      beef_path = Enum.find(paths, &(&1.slug == "beef"))
      assert beef_path.path == "Food > Meat > Red Meat > Beef"
    end
  end

  describe "attachment and review" do
    test "attach_ingredient/3 is guarded by the unique constraint" do
      taxonomy = taxonomy_fixture()
      nodes = seed_meat_tree(taxonomy)
      ingredient = FoodFixtures.ingredient_fixture()

      assert {:ok, _} =
               Taxonomies.attach_ingredient(ingredient.id, nodes.beef.id, %{source: "manual"})

      assert {:error, changeset} =
               Taxonomies.attach_ingredient(ingredient.id, nodes.beef.id, %{source: "manual"})

      assert %{ingredient_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "review_mapping/2 confirms or overrides a pending AI mapping" do
      taxonomy = taxonomy_fixture()
      nodes = seed_meat_tree(taxonomy)
      ingredient = FoodFixtures.ingredient_fixture(%{name: "Lamb, shoulder, raw"})

      {:ok, mapping} =
        Taxonomies.attach_ingredient(ingredient.id, nodes.beef.id, %{
          source: "ai",
          confidence: 0.4
        })

      assert [pending] = Taxonomies.list_pending_review(taxonomy.id)
      assert pending.id == mapping.id
      assert Taxonomies.count_pending_review(taxonomy.id) == 1

      {:ok, overridden} = Taxonomies.review_mapping(mapping.id, {:override, nodes.lamb.id})
      assert overridden.taxonomy_node_id == nodes.lamb.id
      assert overridden.source == "manual"
      assert overridden.reviewed
      assert is_nil(overridden.confidence)

      assert Taxonomies.list_pending_review(taxonomy.id) == []

      {:ok, second} =
        Taxonomies.attach_ingredient(ingredient.id, nodes.chicken.id, %{
          source: "ai",
          confidence: 0.9
        })

      {:ok, confirmed} = Taxonomies.review_mapping(second, :confirm)
      assert confirmed.reviewed
      assert confirmed.taxonomy_node_id == nodes.chicken.id
    end
  end

  defp ids(ingredients), do: ingredients |> Enum.map(& &1.id) |> Enum.sort()
end
