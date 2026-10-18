defmodule Mehungry.PublishedPlans.GroceryAisle do
  @moduledoc """
  Maps an ingredient's food category onto a friendly **shopping aisle** so the
  published plan's weekly grocery list groups the way people actually shop.

  Ingredient categories come straight from USDA FDC `foodCategory.description`
  (e.g. "Vegetables and Vegetable Products", "Dairy and Egg Products") but USDA
  uses several different category vocabularies (SR Legacy, Foundation,
  WWEIA/FNDDS) and the dev seeds use short names ("Vegetables", "Dairy"). Rather
  than enumerate all ~25+ names, `classify/2` keyword-matches the lowercased
  category name, which is robust across every vocabulary; unknowns fall into
  `:other`.
  """

  # Canonical aisle order (a sensible shop route) as `{key, label}` pairs.
  @ordered [
    {"produce", "Produce"},
    {"meat_seafood", "Meat & Seafood"},
    {"dairy_eggs", "Dairy & Eggs"},
    {"bakery_grains", "Bakery & Grains"},
    {"pantry", "Pantry"},
    {"spices", "Spices & Seasonings"},
    {"beverages", "Beverages"},
    {"other", "Other"}
  ]

  # Keyword → aisle, checked in this order so more specific buckets win before the
  # broad "meat"/"fat"/"oil" catch-alls. Each entry: {aisle_key, [substrings]}.
  @keyword_rules [
    {"produce", ["vegetable", "fruit"]},
    {"dairy_eggs", ["dairy", "egg", "milk", "cheese", "yogurt"]},
    {"spices", ["spice", "herb", "season"]},
    {"beverages", ["beverage", "drink", "alcohol", "juice", "water"]},
    {"meat_seafood",
     [
       "beef",
       "pork",
       "poultry",
       "chicken",
       "turkey",
       "lamb",
       "veal",
       "game",
       "sausage",
       "luncheon",
       "finfish",
       "shellfish",
       "fish",
       "seafood",
       "meat"
     ]},
    {"bakery_grains", ["baked", "cereal", "grain", "pasta", "bread", "baking"]},
    {"pantry",
     [
       "legume",
       "nut",
       "seed",
       "soup",
       "sauce",
       "gravy",
       "fat",
       "oil",
       "sweet",
       "sugar",
       "snack",
       "dessert",
       "canned"
     ]}
  ]

  @doc "The canonical aisle order as `{key, label}` pairs."
  @spec ordered() :: [{String.t(), String.t()}]
  def ordered, do: @ordered

  @doc "The display label for an aisle key (falls back to \"Other\")."
  @spec label(String.t()) :: String.t()
  def label(key) do
    Enum.find_value(@ordered, "Other", fn {k, l} -> if k == key, do: l end)
  end

  @doc """
  Classifies a food category (name + optional USDA code) into an aisle key.
  `nil`/blank/unknown categories (and generic ones like "General") → `"other"`.
  """
  @spec classify(String.t() | nil, String.t() | nil) :: String.t()
  def classify(category_name, _usda_code \\ nil)

  def classify(name, _usda_code) when is_binary(name) do
    normalized = String.downcase(name)

    Enum.find_value(@keyword_rules, "other", fn {aisle, keywords} ->
      if Enum.any?(keywords, &String.contains?(normalized, &1)), do: aisle
    end)
  end

  def classify(_name, _usda_code), do: "other"
end
