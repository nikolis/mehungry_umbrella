# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  @moduledoc """
  Enhanced ingredient search with multi-tier ranking
  """
  
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  @doc """
  Search ingredients using tsvector (searchable column exists in DB only)
  """
  def search_ingredient(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    
    # Build base query - referencing searchable column via fragment
    base_query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("searchable @@ websearch_to_tsquery('english', ?)", ^cleaned_term)
    
    # Apply class filter
    base_query = maybe_filter_by_classes(base_query, classes)
    
    # Add ordering and limit
    query = from i in base_query,
      order_by: [
        desc: fragment("ts_rank_cd(searchable, websearch_to_tsquery('english', ?))", ^cleaned_term)
      ],
      limit: 20
    
    Repo.all(query)
  end

  @doc """
  Search with multi-tier ranking (exact matches first)
  """
  def search_ingredient_ranked(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_pattern = "%#{cleaned_term}%"
    
    # Step 1: Get potential matches using basic LIKE (fast)
    base_query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^search_pattern),
      limit: 100
    
    base_query = maybe_filter_by_classes(base_query, classes)
    candidates = Repo.all(base_query)
    
    # Step 2: Rank in Elixir (more control, no fragment issues)
    candidates
    |> Enum.map(fn ingredient -> {ingredient, calculate_rank(ingredient.name, cleaned_term)} end)
    |> Enum.sort_by(fn {_ingredient, rank} -> rank end)
    |> Enum.map(fn {ingredient, _rank} -> ingredient end)
    |> Enum.take(20)
  end

  @doc """
  Hybrid search: Uses FTS for initial filter, then ranks by relevance
  """
  def search_ingredient_hybrid(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    
    # First pass: Use FTS to get candidates
    fts_query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("searchable @@ websearch_to_tsquery('english', ?)", ^cleaned_term),
      limit: 50
    
    fts_query = maybe_filter_by_classes(fts_query, classes)
    candidates = Repo.all(fts_query)
    
    # Second pass: Rank candidates for best relevance
    candidates
    |> Enum.map(fn ingredient -> {ingredient, calculate_rank(ingredient.name, cleaned_term)} end)
    |> Enum.sort_by(fn {_ingredient, rank} -> rank end)
    |> Enum.map(fn {ingredient, _rank} -> ingredient end)
    |> Enum.take(20)
  end

  @doc """
  USDA-style search mimicking the API behavior
  """
  def search_ingredient_usda_style(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("searchable @@ websearch_to_tsquery('english', ?)", ^cleaned_term),
      order_by: [
        asc: fragment("CASE WHEN i.food_class IN ('Foundation', 'SR Legacy') THEN 1 ELSE 2 END"),
        desc: fragment("ts_rank_cd(searchable, websearch_to_tsquery('english', ?))", ^cleaned_term)
      ],
      limit: 20
    
    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # Simple LIKE search as fallback
  def search_ingredient_simple(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    search_pattern = "%#{cleaned_term}%"
    
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^search_pattern),
      order_by: [asc: i.name],
      limit: 20
    
    query
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # Ranking function (higher priority = lower number)
  defp calculate_rank(name, search_term) do
    name_lower = String.downcase(name)
    search_lower = String.downcase(search_term)
    
    cond do
      # Exact match (highest priority)
      name_lower == search_lower -> 1
      name_lower == "#{search_lower}," -> 1
      name_lower == "#{search_lower} " -> 1
      
      # Starts with search term
      String.starts_with?(name_lower, search_lower) -> 2
      
      # Contains as whole word
      String.contains?(name_lower, " #{search_lower} ") -> 3
      String.contains?(name_lower, " #{search_lower},") -> 3
      String.ends_with?(name_lower, " #{search_lower}") -> 3
      
      # Contains search term
      String.contains?(name_lower, search_lower) -> 4
      
      # Fallback
      true -> 5
    end
  end

  # Helper functions
  defp maybe_filter_by_classes(query, nil), do: query
  defp maybe_filter_by_classes(query, []), do: query
  defp maybe_filter_by_classes(query, [""]), do: query
  defp maybe_filter_by_classes(query, classes) do
    from i in query, where: i.food_class in ^classes
  end

  defp get_second_layer_foods_ids do
    # Your existing logic for secondary IDs
    # Example: Get IDs of secondary categories
    # from(c in Category, where: c.name == "Secondary", select: c.id) |> Repo.all()
    []
  end
end
