defmodule Mehungry.Food.TaxonomySeeder do
  @moduledoc """
  Seeds the first ingredient taxonomy: "Biological / Nutritional".

  The tree is curated by hand — USDA food-group codes are too coarse to give
  levels like "Red Meat". Seeding is idempotent: taxonomies and nodes are
  looked up by slug and only created when missing, so the task can be re-run
  after adding nodes to `@tree`.

  The "Other / Unclassified" leaf is load-bearing: the AI classifier uses it
  as the fallback assignment, which guarantees every ingredient eventually
  gets a mapping and the classification worker terminates.
  """

  alias Mehungry.Food.Taxonomies

  @taxonomy %{
    name: "Biological / Nutritional",
    slug: "bio-nutritional",
    description:
      "Groups ingredients by what they are biologically and nutritionally, " <>
        "e.g. Meat > Red Meat > Beef."
  }

  # {name, children} — slugs are derived from names.
  @tree [
    {"Meat",
     [
       {"Red Meat", [{"Beef", []}, {"Lamb", []}, {"Pork", []}, {"Goat", []}, {"Veal", []}]},
       {"Poultry", [{"Chicken", []}, {"Turkey", []}, {"Duck", []}, {"Other Poultry", []}]},
       {"Game Meat", []},
       {"Organ Meat", []},
       {"Processed Meat", []}
     ]},
    {"Fish & Seafood",
     [
       {"Fatty Fish", []},
       {"Lean Fish", []},
       {"Crustaceans", []},
       {"Mollusks", []},
       {"Other Seafood", []}
     ]},
    {"Dairy & Eggs",
     [
       {"Milk", []},
       {"Yogurt & Fermented Dairy", []},
       {"Cheese", []},
       {"Cream & Butter", []},
       {"Eggs", []}
     ]},
    {"Vegetables",
     [
       {"Leafy Greens", []},
       {"Cruciferous Vegetables", []},
       {"Root Vegetables", []},
       {"Nightshades", []},
       {"Alliums", []},
       {"Squashes & Gourds", []},
       {"Stalks & Shoots", []},
       {"Mushrooms", []},
       {"Sea Vegetables", []},
       {"Other Vegetables", []}
     ]},
    {"Fruits",
     [
       {"Berries", []},
       {"Citrus Fruits", []},
       {"Stone Fruits", []},
       {"Pome Fruits", []},
       {"Tropical Fruits", []},
       {"Melons", []},
       {"Dried Fruits", []},
       {"Other Fruits", []}
     ]},
    {"Grains & Cereals",
     [
       {"Whole Grains", []},
       {"Refined Grains", []},
       {"Breads & Baked Grains", []},
       {"Pasta & Noodles", []},
       {"Breakfast Cereals", []}
     ]},
    {"Legumes",
     [{"Beans", []}, {"Lentils", []}, {"Peas", []}, {"Soy Products", []}, {"Peanuts", []}]},
    {"Nuts & Seeds", [{"Tree Nuts", []}, {"Seeds", []}, {"Nut & Seed Butters", []}]},
    {"Fats & Oils", [{"Plant Oils", []}, {"Animal Fats", []}]},
    {"Herbs & Spices", [{"Fresh Herbs", []}, {"Dried Herbs & Spices", []}, {"Salt & Blends", []}]},
    {"Sweeteners", [{"Sugars & Syrups", []}, {"Honey", []}, {"Sugar Substitutes", []}]},
    {"Condiments & Sauces", []},
    {"Beverages",
     [
       {"Water", []},
       {"Juices", []},
       {"Coffee & Tea", []},
       {"Soft Drinks", []},
       {"Alcoholic Beverages", []},
       {"Plant Milks", []}
     ]},
    {"Sweets & Snacks",
     [{"Chocolate & Confectionery", []}, {"Baked Sweets", []}, {"Savory Snacks", []}]},
    {"Prepared & Composite Foods",
     [{"Soups & Stews", []}, {"Fast Food", []}, {"Ready Meals", []}, {"Baby Food", []}]},
    {"Supplements & Additives", []},
    {"Other / Unclassified", []}
  ]

  @doc """
  Idempotently creates the Biological/Nutritional taxonomy and its node tree.
  Returns the taxonomy.
  """
  def seed do
    taxonomy =
      case Taxonomies.get_taxonomy_by_slug(@taxonomy.slug) do
        nil ->
          {:ok, taxonomy} = Taxonomies.create_taxonomy(@taxonomy)
          taxonomy

        taxonomy ->
          taxonomy
      end

    seed_nodes(taxonomy, @tree, nil)
    taxonomy
  end

  defp seed_nodes(taxonomy, children, parent_id) do
    children
    |> Enum.with_index()
    |> Enum.each(fn {{name, grandchildren}, position} ->
      node = get_or_create_node(taxonomy, name, parent_id, position)
      seed_nodes(taxonomy, grandchildren, node.id)
    end)
  end

  defp get_or_create_node(taxonomy, name, parent_id, position) do
    slug = slugify(name)

    case Taxonomies.get_node_by_slug(taxonomy.id, slug) do
      nil ->
        {:ok, node} =
          Taxonomies.create_node(%{
            taxonomy_id: taxonomy.id,
            parent_id: parent_id,
            name: name,
            slug: slug,
            position: position
          })

        node

      node ->
        node
    end
  end

  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
