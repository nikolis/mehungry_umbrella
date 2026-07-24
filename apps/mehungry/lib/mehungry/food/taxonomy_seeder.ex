defmodule Mehungry.Food.TaxonomySeeder do
  @moduledoc """
  Idempotently seeds the first curated taxonomy, "Biological / Nutritional"
  (slug `bio-nutritional`), as nested literal data. Re-running is safe: nodes
  are matched by `(taxonomy_id, slug)` and only created when missing.

  The tree includes an **"Other / Unclassified"** leaf that the classification
  worker relies on as a fallback so every ingredient eventually receives a row.
  """

  alias Mehungry.Food.Taxonomies

  @taxonomy %{name: "Biological / Nutritional", slug: "bio-nutritional"}

  # {name, slug, children}
  @tree [
    {"Meat", "meat",
     [
       {"Red Meat", "red-meat",
        [
          {"Beef", "beef", []},
          {"Lamb", "lamb", []},
          {"Pork", "pork", []},
          {"Goat", "goat", []}
        ]},
       {"Poultry", "poultry",
        [
          {"Chicken", "chicken", []},
          {"Turkey", "turkey", []},
          {"Duck", "duck", []}
        ]},
       {"Game", "game", []}
     ]},
    {"Fish & Seafood", "fish-seafood",
     [
       {"Fatty Fish", "fatty-fish", []},
       {"Lean Fish", "lean-fish", []},
       {"Crustaceans", "crustaceans", []},
       {"Mollusks", "mollusks", []}
     ]},
    {"Dairy & Eggs", "dairy-eggs",
     [
       {"Milk", "milk", []},
       {"Cheese", "cheese", []},
       {"Yogurt", "yogurt", []},
       {"Butter & Cream", "butter-cream", []},
       {"Eggs", "eggs", []}
     ]},
    {"Vegetables", "vegetables",
     [
       {"Leafy Greens", "leafy-greens", []},
       {"Cruciferous", "cruciferous", []},
       {"Root Vegetables", "root-vegetables", []},
       {"Nightshades", "nightshades", []},
       {"Alliums", "alliums", []},
       {"Squashes", "squashes", []},
       {"Mushrooms", "mushrooms", []}
     ]},
    {"Fruits", "fruits",
     [
       {"Berries", "berries", []},
       {"Citrus", "citrus", []},
       {"Stone Fruits", "stone-fruits", []},
       {"Pome Fruits", "pome-fruits", []},
       {"Tropical Fruits", "tropical-fruits", []},
       {"Melons", "melons", []}
     ]},
    {"Grains & Cereals", "grains-cereals",
     [
       {"Whole Grains", "whole-grains", []},
       {"Refined Grains", "refined-grains", []},
       {"Breakfast Cereals", "breakfast-cereals", []},
       {"Bread & Bakery", "bread-bakery", []},
       {"Pasta", "pasta", []}
     ]},
    {"Legumes", "legumes",
     [
       {"Beans", "beans", []},
       {"Lentils", "lentils", []},
       {"Peas", "peas", []},
       {"Soy Products", "soy-products", []}
     ]},
    {"Nuts & Seeds", "nuts-seeds",
     [
       {"Tree Nuts", "tree-nuts", []},
       {"Peanuts", "peanuts", []},
       {"Seeds", "seeds", []},
       {"Nut & Seed Butters", "nut-seed-butters", []}
     ]},
    {"Fats & Oils", "fats-oils",
     [
       {"Vegetable Oils", "vegetable-oils", []},
       {"Animal Fats", "animal-fats", []}
     ]},
    {"Herbs & Spices", "herbs-spices",
     [
       {"Fresh Herbs", "fresh-herbs", []},
       {"Dried Spices", "dried-spices", []}
     ]},
    {"Sweeteners", "sweeteners",
     [
       {"Sugars", "sugars", []},
       {"Syrups & Honey", "syrups-honey", []},
       {"Sugar Substitutes", "sugar-substitutes", []}
     ]},
    {"Beverages", "beverages",
     [
       {"Water", "water", []},
       {"Coffee & Tea", "coffee-tea", []},
       {"Juices", "juices", []},
       {"Soft Drinks", "soft-drinks", []},
       {"Alcoholic Beverages", "alcoholic-beverages", []}
     ]},
    {"Prepared & Composite Foods", "prepared-composite",
     [
       {"Soups & Sauces", "soups-sauces", []},
       {"Snacks", "snacks", []},
       {"Ready Meals", "ready-meals", []},
       {"Condiments", "condiments", []}
     ]},
    {"Other / Unclassified", "other-unclassified", []}
  ]

  @doc "Upserts the taxonomy and its full node tree. Returns the taxonomy."
  def seed do
    taxonomy = upsert_taxonomy()
    seed_children(taxonomy, nil, @tree)
    taxonomy
  end

  defp upsert_taxonomy do
    case Taxonomies.get_taxonomy_by_slug(@taxonomy.slug) do
      nil ->
        {:ok, taxonomy} = Taxonomies.create_taxonomy(@taxonomy)
        taxonomy

      taxonomy ->
        taxonomy
    end
  end

  defp seed_children(taxonomy, parent, children) do
    children
    |> Enum.with_index()
    |> Enum.each(fn {{name, slug, grandchildren}, position} ->
      node = upsert_node(taxonomy, parent, name, slug, position)
      seed_children(taxonomy, node, grandchildren)
    end)
  end

  defp upsert_node(taxonomy, parent, name, slug, position) do
    case Taxonomies.get_node_by_slug(taxonomy.id, slug) do
      nil ->
        {:ok, node} =
          Taxonomies.create_node(%{
            name: name,
            slug: slug,
            position: position,
            taxonomy_id: taxonomy.id,
            parent_id: parent && parent.id
          })

        node

      node ->
        node
    end
  end
end
