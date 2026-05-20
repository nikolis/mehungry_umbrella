# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  @moduledoc """
  USDA-style ingredient search with first-word priority
  """
  
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  @doc """
  Search with first-word priority (Pure Elixir ranking - most reliable)
  """
  def search_optimized(search_term, classes \\ [], limit \\ 20) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Get candidates using simple LIKE (fast)
    candidate_query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^"%#{cleaned_term}%"),
      limit: 100
    
    candidate_query = maybe_filter_by_classes(candidate_query, classes)
    candidates = Repo.all(candidate_query)
    
    # Rank in Elixir (no SQL fragment issues)
    candidates
    |> Enum.map(fn ingredient ->
      score = calculate_usda_score(ingredient.name, search_lower, ingredient.food_class)
      {ingredient, score}
    end)
    |> Enum.sort_by(fn {_ingredient, score} -> -score end)
    |> Enum.map(fn {ingredient, _score} -> ingredient end)
    |> Enum.take(limit)
  end

  @doc """
  Search with trigram similarity for typo tolerance
  """
  def search_fuzzy(search_term, classes \\ [], limit \\ 20) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    
    # Use pg_trgm for similarity matching
    candidate_query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: fragment("LOWER(?) % LOWER(?)", i.name, ^cleaned_term)
        or ilike(i.name, ^"%#{cleaned_term}%"),
      limit: 100
    
    candidate_query = maybe_filter_by_classes(candidate_query, classes)
    candidates = Repo.all(candidate_query)
    
    # Rank with similarity
    candidates
    |> Enum.map(fn ingredient ->
      similarity = calculate_similarity(ingredient.name, search_lower)
      score = calculate_usda_score(ingredient.name, search_lower, ingredient.food_class)
      {ingredient, score + similarity * 10}
    end)
    |> Enum.sort_by(fn {_ingredient, score} -> -score end)
    |> Enum.map(fn {ingredient, _score} -> ingredient end)
    |> Enum.take(limit)
  end

  # USDA-style scoring with first-word priority
  defp calculate_usda_score(name, search_term, food_class) do
    name_lower = String.downcase(name)
    
    # Extract first word (before comma or space)
    first_word = name_lower
      |> String.split(~r/[\s,]+/)
      |> List.first()
      |> to_string()
    
    cond do
      # Exact match (highest priority)
      name_lower == search_term -> 1000
      name_lower == "#{search_term}," -> 1000
      name_lower == "#{search_term} " -> 1000
      name_lower == "#{search_term} -" -> 1000
      
      # First word matches exactly (CRITICAL for "Salt, table")
      first_word == search_term -> 950
      
      # First word starts with search term
      String.starts_with?(first_word, search_term) -> 850
      
      # Any word matches exactly
      String.split(name_lower, ~r/[\s,]+/)
      |> Enum.any?(&(&1 == search_term)) -> 750
      
      # Name starts with search term
      String.starts_with?(name_lower, search_term) -> 650
      
      # Contains as whole word
      String.contains?(name_lower, " #{search_term} ") -> 550
      String.contains?(name_lower, " #{search_term},") -> 550
      String.ends_with?(name_lower, " #{search_term}") -> 550
      
      # Contains search term
      String.contains?(name_lower, search_term) -> 450
      
      # Contains as substring
      true -> 300
    end
    # Add bonus for Foundation/SR Legacy
    |> add_data_type_bonus(food_class)
    # Add bonus for shorter names (more specific)
    |> add_length_bonus(name_lower)
  end

  defp calculate_similarity(name, search_term) do
    name_lower = String.downcase(name)
    # Simple Jaccard-like similarity
    name_words = MapSet.new(String.split(name_lower, ~r/[\s,]+/))
    search_words = MapSet.new(String.split(search_term, ~r/[\s,]+/))
    intersection = MapSet.intersection(name_words, search_words) |> MapSet.size()
    union = MapSet.union(name_words, search_words) |> MapSet.size()
    
    if union > 0 do
      intersection / union
    else
      0
    end
  end

  defp add_data_type_bonus(score, food_class) when food_class in ["Foundation", "SR Legacy"] do
    score + 30
  end
  defp add_data_type_bonus(score, _), do: score

  defp add_length_bonus(score, name) do
    # Shorter names get a small bonus (more specific)
    length_bonus = max(0, 30 - String.length(name))
    score + div(length_bonus, 5)
  end

  # Simple search function for select components (returns limited fields)
  def search_for_select(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^"%#{cleaned_term}%"),
      order_by: [asc: i.name],
      limit: 20,
      select: [:id, :name]
    
    query = maybe_filter_by_classes(query, classes)
    Repo.all(query)
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
