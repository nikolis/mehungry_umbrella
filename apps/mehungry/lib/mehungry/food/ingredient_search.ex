# lib/mehungry/food/ingredient_search.ex

defmodule Mehungry.Food.IngredientSearch do
  @moduledoc """
  USDA-style ingredient search with position-based scoring
  """
  
  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  @doc """
  Smart search with position-based ranking
  """
  def search(search_term, classes \\ [], opts \\ []) do
    cleaned_term = String.trim(search_term)
    search_lower = String.downcase(cleaned_term)
    limit = Keyword.get(opts, :limit, 20)
    detailed = Keyword.get(opts, :detailed, true)
    
    # Return empty if search term is too short
    if String.length(cleaned_term) < 1 do
      return_empty(detailed)
    else
      # Get candidates using simple LIKE (fastest)
      query = from i in Ingredient,
        where: not is_nil(i.name),
        where: i.category_id not in ^get_second_layer_foods_ids(),
        where: ilike(i.name, ^"%#{cleaned_term}%"),
        limit: 100
      
      query = maybe_filter_by_classes(query, classes)
      candidates = Repo.all(query)
      
      # Rank with position-based scoring
      candidates
      |> Enum.map(fn ingredient ->
        score = calculate_position_score(ingredient.name, search_lower, ingredient.food_class)
        {ingredient, score}
      end)
      |> Enum.sort_by(fn {_ingredient, score} -> -score end)
      |> Enum.map(fn {ingredient, _score} -> ingredient end)
      |> Enum.take(limit)
      |> format_results(detailed)
    end
  end

  defp return_empty(true = _detailed), do: []
  defp return_empty(false), do: []

  defp calculate_position_score(name, search_term, food_class) do
    name_lower = String.downcase(name)
    
    # Find position using String.split/pattern matching
    position = find_position(name_lower, search_term)
    
    # Check if it's a standalone word
    is_whole_word = Regex.match?(~r/\b#{Regex.escape(search_term)}\b/, name_lower)
    
    # Get word position
    words = String.split(name_lower, ~r/[\s,]+/)
    word_position = find_word_position(words, search_term)
    
    # Check if preceded by "with"
    has_with_modifier = Regex.match?(~r/with\s+#{Regex.escape(search_term)}/, name_lower)
    
    # Calculate base score
    base_score = cond do
      # Exact match (highest)
      name_lower == search_term -> 1000
      name_lower == "#{search_term}," -> 1000
      name_lower == "#{search_term} " -> 1000
      name_lower == "#{search_term}, " -> 1000
      
      # Name starts with search term
      String.starts_with?(name_lower, search_term) -> 950
      
      # First word is the search term
      List.first(words) == search_term -> 900
      
      # Search term is a standalone word
      is_whole_word -> 800
      
      # Contains as prefix of first word
      (List.first(words) || "") |> String.starts_with?(search_term) -> 700
      
      # Contains as substring anywhere
      true -> 600
    end
    
    # Apply penalties
    position_penalty = cond do
      is_nil(position) -> 0
      position == 0 -> 0
      position <= 5 -> 50
      position <= 15 -> 150
      true -> 250
    end
    
    word_penalty = cond do
      is_nil(word_position) -> 0
      word_position == 0 -> 0
      word_position == 1 -> 100
      word_position == 2 -> 200
      true -> 300
    end
    
    modifier_penalty = if has_with_modifier, do: 200, else: 0
    
    # Calculate final score
    score = base_score - position_penalty - word_penalty - modifier_penalty
    
    # Add bonuses
    score
    |> add_data_type_bonus(food_class)
    |> add_length_bonus(name_lower)
    |> max(0)
  end

  # Helper to find position of substring
  defp find_position(string, substring) do
    case String.split(string, substring, parts: 2) do
      [before, _] -> String.length(before)
      _ -> nil
    end
  end

  # Helper to find word position
  defp find_word_position(words, search_term) do
    Enum.find_index(words, fn word ->
      String.contains?(word, search_term)
    end)
  end

  defp add_data_type_bonus(score, food_class) when food_class in ["Foundation", "SR Legacy"] do
    score + 30
  end
  defp add_data_type_bonus(score, _), do: score

  defp add_length_bonus(score, name) do
    # Shorter, more specific names get a bonus
    length_bonus = max(0, 50 - String.length(name))
    score + div(length_bonus, 10)
  end

  defp format_results(results, true = _detailed), do: results
  defp format_results(results, false) do
    Enum.map(results, fn i -> %{id: i.id, name: i.name} end)
  end

  # Simplified version for select components (fastest)
  def search_for_select(search_term, classes \\ []) do
    search(search_term, classes, detailed: false, limit: 20)
  end

  # Ultra-simple version guaranteed to work
  def search_simple(search_term, classes \\ []) do
    cleaned_term = String.trim(search_term)
    
    query = from i in Ingredient,
      where: not is_nil(i.name),
      where: i.category_id not in ^get_second_layer_foods_ids(),
      where: ilike(i.name, ^"%#{cleaned_term}%"),
      order_by: [
        desc: fragment("CASE WHEN LOWER(?) = LOWER(?) THEN 1 ELSE 0 END", i.name, ^cleaned_term),
        asc: i.name
      ],
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
    []
  end
end
