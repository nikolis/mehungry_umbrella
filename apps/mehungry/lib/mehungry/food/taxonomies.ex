defmodule Mehungry.Food.Taxonomies do
  @moduledoc """
  Hierarchical ingredient taxonomies.

  A `Taxonomy` is an independent tree of concept nodes (`TaxonomyNode`,
  adjacency list via `parent_id`) over the shared ingredient pool; ingredients
  attach to nodes through `IngredientTaxonomyNode` rows that record how the
  mapping was produced (`usda_seed` | `ai` | `manual`), the classifier's
  confidence, and whether an admin has reviewed it.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Ingredient, IngredientTaxonomyNode, Taxonomy, TaxonomyNode}

  # ── Taxonomies ─────────────────────────────────────────────────────────

  def create_taxonomy(attrs) do
    %Taxonomy{}
    |> Taxonomy.changeset(attrs)
    |> Repo.insert()
  end

  def get_taxonomy!(id), do: Repo.get!(Taxonomy, id)

  def get_taxonomy_by_slug(slug), do: Repo.get_by(Taxonomy, slug: slug)

  def list_taxonomies, do: Repo.all(Taxonomy)

  # ── Nodes ──────────────────────────────────────────────────────────────

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
    Repo.get_by(TaxonomyNode, taxonomy_id: taxonomy_id, slug: slug)
  end

  def list_nodes(taxonomy_id) do
    from(n in TaxonomyNode,
      where: n.taxonomy_id == ^taxonomy_id,
      order_by: [asc: n.position, asc: n.name]
    )
    |> Repo.all()
  end

  @doc """
  Nodes of the taxonomy that have no children — the attachment targets the AI
  classifier and the review override select choose from.
  """
  def list_leaf_nodes(taxonomy_id) do
    from(n in TaxonomyNode,
      left_join: c in TaxonomyNode,
      on: c.parent_id == n.id,
      where: n.taxonomy_id == ^taxonomy_id and is_nil(c.id),
      order_by: [asc: n.position, asc: n.name]
    )
    |> Repo.all()
  end

  @doc """
  Leaf nodes annotated with their ancestor path, e.g.
  `%{id: 12, slug: "beef", path: "Meat > Red Meat > Beef"}`.
  """
  def list_leaf_paths(taxonomy_id) do
    nodes = list_nodes(taxonomy_id)
    by_id = Map.new(nodes, &{&1.id, &1})
    children_of = Enum.group_by(nodes, & &1.parent_id)

    nodes
    |> Enum.reject(fn n -> Map.has_key?(children_of, n.id) end)
    |> Enum.map(fn leaf ->
      %{id: leaf.id, slug: leaf.slug, path: build_path(leaf, by_id)}
    end)
  end

  defp build_path(node, by_id, acc \\ [])

  defp build_path(%TaxonomyNode{parent_id: nil} = node, _by_id, acc) do
    Enum.join([node.name | acc], " > ")
  end

  defp build_path(%TaxonomyNode{} = node, by_id, acc) do
    build_path(Map.fetch!(by_id, node.parent_id), by_id, [node.name | acc])
  end

  # ── Tree assembly ──────────────────────────────────────────────────────

  @doc """
  Assembles the taxonomy's persisted nodes into nested
  `%{id, name, slug, amount, measurement_unit, children}` maps — the shape
  `MehungryWeb.AccordionComponent` consumes. `amount` carries the rolled-up
  count of ingredients attached anywhere in the node's subtree.
  """
  def build_tree(taxonomy_id) do
    nodes = list_nodes(taxonomy_id)
    children_of = Enum.group_by(nodes, & &1.parent_id)

    counts =
      from(itn in IngredientTaxonomyNode,
        join: n in TaxonomyNode,
        on: n.id == itn.taxonomy_node_id,
        where: n.taxonomy_id == ^taxonomy_id,
        group_by: itn.taxonomy_node_id,
        select: {itn.taxonomy_node_id, count(itn.id)}
      )
      |> Repo.all()
      |> Map.new()

    children_of
    |> Map.get(nil, [])
    |> Enum.map(&build_tree_node(&1, children_of, counts))
  end

  defp build_tree_node(node, children_of, counts) do
    children =
      children_of
      |> Map.get(node.id, [])
      |> Enum.map(&build_tree_node(&1, children_of, counts))

    rolled_up_count =
      Map.get(counts, node.id, 0) + (children |> Enum.map(& &1.amount) |> Enum.sum())

    %{
      id: node.id,
      name: node.name,
      slug: node.slug,
      amount: rolled_up_count,
      measurement_unit: "foods",
      children: children
    }
  end

  # ── Subtree queries ────────────────────────────────────────────────────

  @doc """
  Ids of the node and all of its descendants, via a recursive CTE over
  `taxonomy_nodes.parent_id`.
  """
  def subtree_node_ids(node_id) do
    Repo.all(subtree_query(node_id))
  end

  defp subtree_query(node_id) do
    base = from(n in TaxonomyNode, where: n.id == ^node_id, select: n.id)

    recursion =
      from(n in TaxonomyNode,
        join: s in "subtree",
        on: n.parent_id == s.id,
        select: n.id
      )

    cte = union_all(base, ^recursion)

    from(s in "subtree", select: s.id)
    |> recursive_ctes(true)
    |> with_cte("subtree", as: ^cte)
  end

  @doc """
  Ingredients attached to the node or any of its descendants.
  """
  def list_ingredients_under_node(node_id) do
    from(i in Ingredient,
      join: itn in IngredientTaxonomyNode,
      on: itn.ingredient_id == i.id,
      where: itn.taxonomy_node_id in subquery(subtree_query(node_id)),
      distinct: i.id,
      order_by: [asc: i.name]
    )
    |> Repo.all()
  end

  # ── Ingredient attachment ──────────────────────────────────────────────

  def attach_ingredient(ingredient_id, taxonomy_node_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.merge(%{
        "ingredient_id" => ingredient_id,
        "taxonomy_node_id" => taxonomy_node_id
      })
      |> Map.put_new("source", "manual")

    %IngredientTaxonomyNode{}
    |> IngredientTaxonomyNode.changeset(attrs)
    |> Repo.insert()
  end

  def detach_ingredient(ingredient_id, taxonomy_node_id) do
    from(itn in IngredientTaxonomyNode,
      where: itn.ingredient_id == ^ingredient_id and itn.taxonomy_node_id == ^taxonomy_node_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Ids of ingredients that have no mapping in the given taxonomy — the AI
  classifier's work queue.
  """
  def unclassified_ingredients_query(taxonomy_id) do
    classified =
      from(itn in IngredientTaxonomyNode,
        join: n in TaxonomyNode,
        on: n.id == itn.taxonomy_node_id,
        where: n.taxonomy_id == ^taxonomy_id,
        select: itn.ingredient_id
      )

    from(i in Ingredient, where: i.id not in subquery(classified))
  end

  # ── Review ─────────────────────────────────────────────────────────────

  @doc """
  Unreviewed mappings for the taxonomy, lowest confidence first (nulls first),
  with ingredient and node preloaded. Options: `:limit` (default 50),
  `:offset` (default 0).
  """
  def list_pending_review(taxonomy_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(itn in IngredientTaxonomyNode,
      join: n in TaxonomyNode,
      on: n.id == itn.taxonomy_node_id,
      where: n.taxonomy_id == ^taxonomy_id and itn.reviewed == false,
      order_by: [asc_nulls_first: itn.confidence, asc: itn.id],
      limit: ^limit,
      offset: ^offset,
      preload: [ingredient: :category, taxonomy_node: :parent]
    )
    |> Repo.all()
  end

  def count_pending_review(taxonomy_id) do
    from(itn in IngredientTaxonomyNode,
      join: n in TaxonomyNode,
      on: n.id == itn.taxonomy_node_id,
      where: n.taxonomy_id == ^taxonomy_id and itn.reviewed == false,
      select: count(itn.id)
    )
    |> Repo.one()
  end

  @doc """
  Resolves a pending mapping: `:confirm` keeps the assigned node, while
  `{:override, node_id}` moves it to the given node as a manual assignment.
  """
  def review_mapping(%IngredientTaxonomyNode{} = mapping, :confirm) do
    mapping
    |> IngredientTaxonomyNode.changeset(%{reviewed: true})
    |> Repo.update()
  end

  def review_mapping(%IngredientTaxonomyNode{} = mapping, {:override, taxonomy_node_id}) do
    mapping
    |> IngredientTaxonomyNode.changeset(%{
      taxonomy_node_id: taxonomy_node_id,
      source: "manual",
      confidence: nil,
      reviewed: true
    })
    |> Repo.update()
  end

  def review_mapping(mapping_id, action) when is_integer(mapping_id) do
    IngredientTaxonomyNode
    |> Repo.get!(mapping_id)
    |> review_mapping(action)
  end
end
