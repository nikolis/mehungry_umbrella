# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  @moduledoc """
  Simple ingredient search that prioritizes exact matches
  """
  
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  @doc """
  Simple, predictable search that puts exact matches first
  """
  def search(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Get all potential matches
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^"%#{cleaned_term}%"),
      limit: 200
    
    query = maybe_filter_by_classes(query, classes)
    candidates = Repo.all(query)
    
    # Split into three categories
    {exact_matches, starts_with_matches, other_matches} = partition_results(candidates, search_lower)
    
    # Combine: exact matches first, then starts with, then others
    exact_matches ++ starts_with_matches ++ other_matches
    |> Enum.take(20)
  end

  defp partition_results(candidates, search_term) do
    Enum.reduce(candidates, {[], [], []}, fn ingredient, {exact, starts, other} ->
      name_lower = String.downcase(ingredient.name)
      
      cond do
        # Exact match (or exact with comma/space)
        name_lower == search_term ->
          {[ingredient | exact], starts, other}
        name_lower == "#{search_term}," ->
          {[ingredient | exact], starts, other}
        name_lower == "#{search_term} " ->
          {[ingredient | exact], starts, other}
        name_lower == "#{search_term}, " ->
          {[ingredient | exact], starts, other}
        
        # Starts with search term (but not exact)
        String.starts_with?(name_lower, search_term) ->
          {exact, [ingredient | starts], other}
        
        # Everything else
        true ->
          {exact, starts, [ingredient | other]}
      end
    end)
  end

  @doc """
  For select components - returns only id and name
  """
  def search_for_select(search_term, classes \\ []) do
    results = search(search_term, classes)
    Enum.map(results, fn i -> %{id: i.id, name: i.name} end)
  end

  # Simple search that prioritizes exact word boundaries
  def search_with_priority(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Build a query that prioritizes exact matches
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^"%#{cleaned_term}%"),
      order_by: [
        desc: fragment("""
          CASE 
            WHEN LOWER(?) = LOWER(?) THEN 3
            WHEN LOWER(?) LIKE LOWER(?) || ',%' THEN 2
            WHEN LOWER(?) LIKE LOWER(?) || ' %' THEN 2
            WHEN LOWER(?) LIKE LOWER(?) || '%' THEN 1
            ELSE 0
          END
        """, 
          i.name, ^cleaned_term,
          i.name, ^cleaned_term,
          i.name, ^cleaned_term,
          i.name, ^cleaned_term
        ),
        asc: i.name
      ],
      limit: 20
    
    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # Helper functions
  defp maybe_filter_by_classes(query, nil), do: query
  defp maybe_filter_by_classes(query, []), do: query
  defp maybe_filter_by_classes(query, [""]), do: query
  defp maybe_filter_by_classes(query, classes) do
    from i in query, where: i.food_class in ^classes
  end

  defp get_second_layer_foods_ids do
    []
  end
end
