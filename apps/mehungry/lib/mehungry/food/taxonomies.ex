defmodule Mehungry.Food.Taxonomies do
  @moduledoc """
  Hierarchical, multi-level taxonomies over the ingredient pool.

  A `Taxonomy` owns a tree of `TaxonomyNode`s (self-referencing via `parent_id`);
  ingredients are attached to nodes through `IngredientTaxonomyNode`. Several
  independent taxonomies may classify the same ingredients.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Ingredient, Taxonomy, TaxonomyNode, IngredientTaxonomyNode}

  # ── Taxonomy CRUD ──────────────────────────────────────────────────────

  def create_taxonomy(attrs) do
    %Taxonomy{}
    |> Taxonomy.changeset(attrs)
    |> Repo.insert()
  end

  def get_taxonomy!(id), do: Repo.get!(Taxonomy, id)

  def get_taxonomy_by_slug(slug) do
    Repo.one(from(t in Taxonomy, where: t.slug == ^slug))
  end

  def list_taxonomies, do: Repo.all(Taxonomy)

  # ── Node CRUD ──────────────────────────────────────────────────────────

  def create_node(attrs) do
    %TaxonomyNode{}
    |> TaxonomyNode.changeset(attrs)
    |> Repo.insert()
  end

  def update_node(%TaxonomyNode{} = node, attrs) do
    node
    |> TaxonomyNode.changeset(attrs)
    |> Repo.update()
  end

  def delete_node(%TaxonomyNode{} = node), do: Repo.delete(node)

  def get_node!(id), do: Repo.get!(TaxonomyNode, id)

  def get_node_by_slug(taxonomy_id, slug) do
    Repo.one(
      from(n in TaxonomyNode, where: n.taxonomy_id == ^taxonomy_id and n.slug == ^slug)
    )
  end

  def list_nodes(taxonomy_id) do
    Repo.all(
      from(n in TaxonomyNode,
        where: n.taxonomy_id == ^taxonomy_id,
        order_by: [asc: n.position, asc: n.id]
      )
    )
  end

  @doc "Nodes with no children — the leaves the classifier assigns ingredients to."
  def list_leaf_nodes(taxonomy_id) do
    Repo.all(
      from(n in TaxonomyNode,
        left_join: c in TaxonomyNode,
        on: c.parent_id == n.id,
        where: n.taxonomy_id == ^taxonomy_id and is_nil(c.id),
        order_by: [asc: n.position, asc: n.id]
      )
    )
  end

  @doc """
  Leaf nodes with their full ancestor path (e.g. `"Meat > Red Meat > Beef"`).
  Feeds the AI classifier, which identifies a leaf by `slug`.
  """
  def list_leaves_with_paths(taxonomy_id) do
    nodes = list_nodes(taxonomy_id)
    by_id = Map.new(nodes, &{&1.id, &1})
    by_parent = Enum.group_by(nodes, & &1.parent_id)

    for node <- nodes, Map.get(by_parent, node.id, []) == [] do
      %{id: node.id, slug: node.slug, path: node_path(node, by_id)}
    end
  end

  defp node_path(%TaxonomyNode{parent_id: nil} = node, _by_id), do: node.name

  defp node_path(%TaxonomyNode{parent_id: parent_id} = node, by_id) do
    node_path(Map.fetch!(by_id, parent_id), by_id) <> " > " <> node.name
  end

  # ── Tree assembly ──────────────────────────────────────────────────────

  @doc """
  Whole taxonomy as nested maps in the shape `AccordionComponent.accordion/1`
  consumes: `%{id, name, slug, amount: rolled_up_count, measurement_unit:
  "foods", children: [...]}`. `amount` is the node's own mappings plus every
  descendant's. Two queries total (nodes + grouped counts).
  """
  def build_tree(taxonomy_id) do
    nodes = list_nodes(taxonomy_id)

    direct_counts =
      from(itn in IngredientTaxonomyNode,
        join: n in TaxonomyNode,
        on: n.id == itn.taxonomy_node_id,
        where: n.taxonomy_id == ^taxonomy_id,
        group_by: itn.taxonomy_node_id,
        select: {itn.taxonomy_node_id, count(itn.id)}
      )
      |> Repo.all()
      |> Map.new()

    by_parent = Enum.group_by(nodes, & &1.parent_id)

    by_parent
    |> Map.get(nil, [])
    |> Enum.map(&build_node(&1, by_parent, direct_counts))
  end

  defp build_node(node, by_parent, direct_counts) do
    children =
      by_parent
      |> Map.get(node.id, [])
      |> Enum.map(&build_node(&1, by_parent, direct_counts))

    own = Map.get(direct_counts, node.id, 0)
    rolled_up = own + Enum.sum(Enum.map(children, & &1.amount))

    %{
      id: node.id,
      name: node.name,
      slug: node.slug,
      amount: rolled_up,
      measurement_unit: "foods",
      children: children
    }
  end

  # ── Subtree / ingredient queries ───────────────────────────────────────

  @doc "All node ids in the subtree rooted at `node_id` (inclusive), via recursive CTE."
  def subtree_node_ids(node_id) do
    node_id
    |> subtree_query()
    |> Repo.all()
    |> Enum.map(& &1.id)
  end

  # Recursive CTE walking `taxonomy_nodes.parent_id` down from `node_id`.
  # First recursive-CTE use in the repo. Returns a query selecting %{id: id}.
  defp subtree_query(node_id) do
    base =
      from(n in "taxonomy_nodes",
        where: n.id == ^node_id,
        select: %{id: n.id}
      )

    recursion =
      from(n in "taxonomy_nodes",
        join: s in "subtree",
        on: n.parent_id == s.id,
        select: %{id: n.id}
      )

    union = union_all(base, ^recursion)

    from(s in "subtree")
    |> recursive_ctes(true)
    |> with_cte("subtree", as: ^union)
    |> select([s], %{id: s.id})
  end

  @doc "Distinct ingredients attached to any node in the subtree rooted at `node_id`."
  def list_ingredients_under_node(node_id) do
    from(i in Ingredient,
      join: itn in IngredientTaxonomyNode,
      on: itn.ingredient_id == i.id,
      where: itn.taxonomy_node_id in subquery(subtree_query(node_id)),
      distinct: true
    )
    |> Repo.all()
  end

  # ── Attach / detach ────────────────────────────────────────────────────

  def attach_ingredient(ingredient_id, node_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{})
      |> Map.put(:ingredient_id, ingredient_id)
      |> Map.put(:taxonomy_node_id, node_id)
      |> Map.put_new(:source, "manual")

    %IngredientTaxonomyNode{}
    |> IngredientTaxonomyNode.changeset(attrs)
    |> Repo.insert()
  end

  def detach_ingredient(ingredient_id, node_id) do
    from(itn in IngredientTaxonomyNode,
      where: itn.ingredient_id == ^ingredient_id and itn.taxonomy_node_id == ^node_id
    )
    |> Repo.delete_all()
  end

  # ── Review ─────────────────────────────────────────────────────────────

  @doc """
  Unreviewed mappings for a taxonomy, lowest-confidence first (nulls first),
  ingredient + node preloaded. `opts`: `:limit` (default 50), `:offset`.
  """
  def list_pending_review(taxonomy_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(itn in IngredientTaxonomyNode,
      join: n in TaxonomyNode,
      on: n.id == itn.taxonomy_node_id,
      where: n.taxonomy_id == ^taxonomy_id and itn.reviewed == false,
      order_by: [asc_nulls_first: itn.confidence, asc: itn.id],
      preload: [ingredient: :category, taxonomy_node: []],
      limit: ^limit,
      offset: ^offset
    )
    |> Repo.all()
  end

  def review_mapping(id, :confirm) do
    IngredientTaxonomyNode
    |> Repo.get!(id)
    |> IngredientTaxonomyNode.changeset(%{reviewed: true})
    |> Repo.update()
  end

  def review_mapping(id, {:override, new_node_id}) do
    IngredientTaxonomyNode
    |> Repo.get!(id)
    |> IngredientTaxonomyNode.changeset(%{
      taxonomy_node_id: new_node_id,
      source: "manual",
      reviewed: true,
      confidence: nil
    })
    |> Repo.update()
  end
end
