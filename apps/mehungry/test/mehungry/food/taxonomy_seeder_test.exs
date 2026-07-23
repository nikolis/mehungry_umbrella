defmodule Mehungry.Food.TaxonomySeederTest do
  use Mehungry.DataCase

  alias Mehungry.Food.{Taxonomies, TaxonomySeeder}

  test "seed/0 creates the bio-nutritional tree and is idempotent" do
    taxonomy = TaxonomySeeder.seed()
    assert taxonomy.slug == "bio-nutritional"

    nodes = Taxonomies.list_nodes(taxonomy.id)
    assert length(nodes) > 50

    # The classifier's fallback leaf must exist and be a leaf.
    fallback = Taxonomies.get_node_by_slug(taxonomy.id, "other-unclassified")
    assert fallback
    assert fallback.id in Enum.map(Taxonomies.list_leaf_nodes(taxonomy.id), & &1.id)

    # Multi-level structure: Meat > Red Meat > Beef.
    beef = Taxonomies.get_node_by_slug(taxonomy.id, "beef")
    red_meat = Taxonomies.get_node_by_slug(taxonomy.id, "red-meat")
    meat = Taxonomies.get_node_by_slug(taxonomy.id, "meat")
    assert beef.parent_id == red_meat.id
    assert red_meat.parent_id == meat.id
    assert is_nil(meat.parent_id)

    same_taxonomy = TaxonomySeeder.seed()
    assert same_taxonomy.id == taxonomy.id
    assert length(Taxonomies.list_nodes(taxonomy.id)) == length(nodes)
  end
end
