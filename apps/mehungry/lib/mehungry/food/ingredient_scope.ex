defmodule Mehungry.Food.IngredientScope do
  @moduledoc """
  Shared Ecto query scopes for ingredient search — owner/friends visibility, USDA
  food-class filtering, and hiding the composite/prepared "second layer" categories.

  Both search paths compose these so the rules stay identical everywhere:
  `Mehungry.Food.IngredientSearch` (ranked prefix+fuzzy) and
  `Mehungry.Food.IngredientQueries` (full-text / admin variants). Each helper
  assumes the ingredient is the **first** binding of the query it receives.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Food.Categories

  # The composite/prepared USDA "second layer" categories hidden from user-facing
  # ingredient search — prepared dishes, snacks, drinks etc. that aren't useful as
  # recipe building blocks.
  @second_layer_titles [
    "Meals, Entrees, and Side Dishes",
    "Restaurant Foods",
    "Baked Products",
    "Snacks",
    "Sweets",
    "Baby Foods",
    "Breakfast Cereals",
    "Beverages"
  ]

  @doc """
  Category ids of the composite/prepared USDA "second layer" categories, resolved
  by name (absent categories are skipped). Both search paths hide these from
  user-facing results via `exclude_secondary_categories/3`.
  """
  def second_layer_category_ids do
    @second_layer_titles
    |> Enum.map(fn title ->
      case Categories.get_category_by_name(title) do
        nil -> nil
        category -> category.id
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Hides the composite/prepared "second layer" categories from ingredient search —
  but never the viewer's own private ingredients. A user deliberately picks the
  category for an ingredient they created, so it must stay searchable for them
  regardless of which category that is. Assumes the ingredient is the first binding.
  """
  def exclude_secondary_categories(query, [], _owner_id), do: query

  def exclude_secondary_categories(query, secondary_ids, nil) do
    from(i in query, where: i.category_id not in ^secondary_ids)
  end

  def exclude_secondary_categories(query, secondary_ids, owner_id) do
    ids = visible_owner_ids(owner_id)

    from(i in query,
      where: i.category_id not in ^secondary_ids or i.user_id in ^ids
    )
  end

  @doc """
  Visibility filter: global rows (`user_id IS NULL`) are always returned; when a
  viewer id is given, their own private rows and their friends' are included too.
  Branches on nil because Ecto forbids `== nil` comparisons.
  """
  def filter_by_owner(query, nil), do: from(i in query, where: is_nil(i.user_id))

  def filter_by_owner(query, owner_id) do
    ids = visible_owner_ids(owner_id)
    from(i in query, where: is_nil(i.user_id) or i.user_id in ^ids)
  end

  @doc """
  The set of user ids whose private ingredients `owner_id` may see: themselves
  plus their friends (blanket sharing via `Mehungry.Friends`).
  """
  def visible_owner_ids(owner_id) do
    [owner_id | Mehungry.Friends.friend_ids(owner_id)]
  end

  @doc "Restrict a query to the given USDA food classes; no-op for nil/empty."
  def maybe_filter_by_classes(query, nil), do: query
  def maybe_filter_by_classes(query, []), do: query
  def maybe_filter_by_classes(query, [""]), do: query

  def maybe_filter_by_classes(query, classes) do
    from(i in query, where: i.food_class in ^classes)
  end
end
